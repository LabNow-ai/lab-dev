#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const DEFAULT_CONFIG = {
  agents: {
    defaults: {
      workspace: '/opt/openclaw/data/workspace'
    }
  },
  gateway: {
    controlUi: {
      dangerouslyAllowHostHeaderOriginFallback: true,
      dangerouslyDisableDeviceAuth: true
    }
  }
};

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      args._.push(token);
      continue;
    }

    const eqIndex = token.indexOf('=');
    if (eqIndex > -1) {
      const key = token.slice(2, eqIndex);
      const value = token.slice(eqIndex + 1);
      args[key] = value;
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }

    args[key] = next;
    i += 1;
  }

  return args;
}

function parseCommaList(value) {
  if (!value || value === true) return [];
  return String(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function pluginIdFromPackage(packageName) {
  return packageName.split('/').pop();
}

function ensureConfigShape(config) {
  if (!config.plugins) config.plugins = {};
  if (!Array.isArray(config.plugins.allow)) config.plugins.allow = [];
  if (!config.plugins.entries) config.plugins.entries = {};
}

function loadConfig(configPath) {
  const raw = fs.readFileSync(configPath, 'utf8');
  return JSON.parse(raw);
}

function saveConfig(configPath, config) {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
}

function ensureConfigFile(configPath, templatePath) {
  fs.mkdirSync(path.dirname(configPath), { recursive: true });
  if (fs.existsSync(configPath) && fs.statSync(configPath).size > 0) {
    return;
  }

  if (templatePath && fs.existsSync(templatePath)) {
    fs.copyFileSync(templatePath, configPath);
    return;
  }

  saveConfig(configPath, DEFAULT_CONFIG);
}

function mergeDefaultConfig(configPath) {
  const config = loadConfig(configPath);

  if (!config.agents) config.agents = {};
  if (!config.agents.defaults) config.agents.defaults = {};
  if (!config.agents.defaults.workspace) {
    config.agents.defaults.workspace = DEFAULT_CONFIG.agents.defaults.workspace;
  }

  if (!config.gateway) config.gateway = {};
  if (!config.gateway.controlUi) config.gateway.controlUi = {};
  if (typeof config.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback !== 'boolean') {
    config.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback = true;
  }
  if (typeof config.gateway.controlUi.dangerouslyDisableDeviceAuth !== 'boolean') {
    config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
  }

  saveConfig(configPath, config);
}

function runOpenclawInstall(packageName, env) {
  const result = spawnSync('openclaw', ['plugins', 'install', packageName], {
    encoding: 'utf8',
    env
  });

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);

  if (result.status === 0) {
    return { ok: true, alreadyExists: false };
  }

  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (output.includes('plugin already exists')) {
    return { ok: true, alreadyExists: true };
  }

  const err = new Error(`Command failed: openclaw plugins install ${packageName}`);
  err.status = result.status;
  err.output = output;
  throw err;
}

function safeRemove(targetPath) {
  if (!fs.existsSync(targetPath)) return;
  const stat = fs.lstatSync(targetPath);
  if (stat.isDirectory() && !stat.isSymbolicLink()) {
    fs.rmSync(targetPath, { recursive: true, force: true });
  } else {
    fs.unlinkSync(targetPath);
  }
}

function ensurePluginAtTarget(options) {
  const { homeClaw, stateDir, extensionsDir, pluginDirName } = options;
  const targetPath = path.join(extensionsDir, pluginDirName);

  if (fs.existsSync(targetPath)) {
    return targetPath;
  }

  const candidates = [
    path.join(stateDir, '.openclaw', 'extensions', pluginDirName),
    path.join(homeClaw, '.openclaw', 'extensions', pluginDirName),
    path.join('/opt/openclaw', '.openclaw', 'extensions', pluginDirName),
    path.join(homeClaw, 'extensions', pluginDirName)
  ];

  const actualPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!actualPath) {
    return '';
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });

  try {
    fs.renameSync(actualPath, targetPath);
  } catch (err) {
    if (!err || err.code !== 'EXDEV') throw err;
    fs.cpSync(actualPath, targetPath, { recursive: true });
    safeRemove(actualPath);
  }

  fs.mkdirSync(path.dirname(actualPath), { recursive: true });
  safeRemove(actualPath);
  fs.symlinkSync(targetPath, actualPath, 'dir');

  return targetPath;
}

function applyInstallConfig(configPath, pluginId) {
  const config = loadConfig(configPath);
  ensureConfigShape(config);

  if (!config.plugins.allow.includes(pluginId)) {
    config.plugins.allow.push(pluginId);
  }
  config.plugins.entries[pluginId] = { enabled: true };

  saveConfig(configPath, config);
}

function applyDisableConfig(configPath, entryIds) {
  const config = loadConfig(configPath);
  ensureConfigShape(config);

  for (const entryId of entryIds) {
    config.plugins.entries[entryId] = { enabled: false };
  }

  saveConfig(configPath, config);
}

function installCommand(args) {
  const packageName = args.package;
  const configPath = args.config;
  const homeClaw = path.resolve(args.home || '/opt/openclaw');
  const stateDir = path.resolve(args['state-dir'] || path.dirname(configPath || ''));
  const extensionsDir = path.resolve(args['extensions-dir'] || path.join(stateDir, 'extensions'));
  const pluginId = args.id || pluginIdFromPackage(packageName || '');
  const pluginDirName = args['plugin-dir'] || pluginId;
  const forceInstall = Boolean(args.force);
  const templatePath = args.template || '';

  if (!packageName || !configPath) {
    throw new Error('Missing required args: --package, --config');
  }

  ensureConfigFile(configPath, templatePath);
  mergeDefaultConfig(configPath);

  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(extensionsDir, { recursive: true });

  const targetPath = path.join(extensionsDir, pluginDirName);
  const installEnv = {
    ...process.env,
    OPENCLAW_DIR_STATE: stateDir,
    OPENCLAW_DIR_EXTENSIONS: extensionsDir,
    XDG_CONFIG_HOME: stateDir,
    OPENCLAW_EXTENSIONS_DIR: extensionsDir
  };

  if (forceInstall || !fs.existsSync(targetPath)) {
    console.log(`[plugin-installer] Installing ${packageName} ...`);
    const result = runOpenclawInstall(packageName, installEnv);
    if (result.alreadyExists) {
      console.log(`[plugin-installer] ${pluginId} already exists, treat as idempotent success.`);
    }
  } else {
    console.log(`[plugin-installer] ${pluginId} already exists at ${targetPath}, skip install.`);
  }

  const finalPath = ensurePluginAtTarget({ homeClaw, stateDir, extensionsDir, pluginDirName });
  if (!finalPath) {
    console.warn(`[plugin-installer] WARN: unable to locate installed plugin ${pluginId}.`);
  } else {
    console.log(`[plugin-installer] plugin path: ${finalPath}`);
  }

  applyInstallConfig(configPath, pluginId);
  console.log(`[plugin-installer] ${packageName} install flow completed.`);
}

function disableCommand(args) {
  const configPath = args.config;
  const entryIds = parseCommaList(args.entry || args.entries);

  if (!configPath || entryIds.length === 0) {
    throw new Error('Missing required args: --config, --entry <id[,id2]>');
  }

  ensureConfigFile(configPath, args.template || '');
  mergeDefaultConfig(configPath);
  applyDisableConfig(configPath, entryIds);
  console.log(`[plugin-installer] disabled entries: ${entryIds.join(', ')}`);
}

function initConfigCommand(args) {
  const configPath = args.config;
  if (!configPath) {
    throw new Error('Missing required args: --config');
  }

  ensureConfigFile(configPath, args.template || '');
  mergeDefaultConfig(configPath);
  console.log(`[plugin-installer] config ready: ${configPath}`);
}

function printHelp() {
  console.log(`Usage:
  node openclaw-plugin-installer.js <command> [options]

Commands:
  init-config   Ensure config file exists and apply default base settings
  install       Install plugin package and enable corresponding plugin entry
  disable       Disable plugin entries in config

Common options:
  --config <path>            OpenClaw config path
  --template <path>          Config template path (optional)

Install options:
  --package <pkg>            NPM package, e.g. @larksuite/openclaw-lark
  --id <plugin-id>           Optional plugin id (default: package basename)
  --home <path>              OpenClaw home (default: /opt/openclaw)
  --state-dir <path>         State dir (default: dirname(--config))
  --extensions-dir <path>    Extensions dir (default: <state-dir>/extensions)
  --plugin-dir <name>        Plugin directory name (default: plugin id)
  --force                    Force install even if target plugin dir exists

Disable options:
  --entry <id[,id2]>         Comma separated plugin entry ids to disable
`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = args._[0];

  if (!command || command === 'help' || command === '--help') {
    printHelp();
    process.exit(command ? 0 : 1);
  }

  if (command === 'init-config') {
    initConfigCommand(args);
    return;
  }

  if (command === 'install') {
    installCommand(args);
    return;
  }

  if (command === 'disable') {
    disableCommand(args);
    return;
  }

  throw new Error(`Unsupported command: ${command}`);
}

try {
  main();
} catch (err) {
  console.error(`[plugin-installer] ${err.message}`);
  if (err.output) {
    console.error(err.output);
  }
  process.exit(1);
}
