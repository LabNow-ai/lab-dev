#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

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

function pluginDirectoryCandidates(homeClaw, pluginDirName, extensionsDir) {
  const roots = new Set();
  const normalizedHome = homeClaw && path.resolve(homeClaw);

  if (extensionsDir) roots.add(path.resolve(extensionsDir));
  if (normalizedHome) {
    roots.add(path.join(normalizedHome, 'extensions'));
    roots.add(path.join(normalizedHome, '.openclaw', 'extensions'));
  }
  roots.add(path.join('/opt/openclaw', '.openclaw', 'extensions'));

  return Array.from(roots).map((root) => path.join(root, pluginDirName));
}

function pluginDirectoryExists(homeClaw, pluginDirName, extensionsDir) {
  const candidates = pluginDirectoryCandidates(homeClaw, pluginDirName, extensionsDir);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return { exists: true, path: candidate };
    }
  }
  return { exists: false, path: '' };
}

function installOpenclawPlugin(packageName, env) {
  const result = spawnSync('openclaw', ['plugins', 'install', packageName], {
    encoding: 'utf8',
    env
  });

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);

  if (result.status === 0) {
    return { installed: true, alreadyExists: false };
  }

  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (output.includes('plugin already exists')) {
    return { installed: false, alreadyExists: true };
  }

  const err = new Error(`Command failed: openclaw plugins install ${packageName}`);
  err.status = result.status;
  err.output = output;
  throw err;
}

function applyPluginConfig(config, pluginId, disableEntries) {
  ensureConfigShape(config);

  if (!config.plugins.allow.includes(pluginId)) {
    config.plugins.allow.push(pluginId);
  }

  config.plugins.entries[pluginId] = { enabled: true };

  for (const entryId of disableEntries) {
    config.plugins.entries[entryId] = { enabled: false };
  }
}

function installPlugin(options) {
  const {
    homeClaw,
    configPath,
    packageName,
    pluginId,
    pluginDirName,
    forceInstall,
    stateDir,
    extensionsDir,
    disableEntries
  } = options;

  fs.mkdirSync(stateDir, { recursive: true });
  fs.mkdirSync(extensionsDir, { recursive: true });

  const installEnv = {
    ...process.env,
    OPENCLAW_DIR_STATE: stateDir,
    OPENCLAW_DIR_EXTENSIONS: extensionsDir,
    XDG_CONFIG_HOME: stateDir
  };

  const existence = pluginDirectoryExists(homeClaw, pluginDirName, extensionsDir);
  const needInstall = forceInstall || !existence.exists;

  if (!needInstall) {
    console.log(`[plugin-installer] ${pluginId} already exists at ${existence.path}, skip install.`);
  } else {
    console.log(`[plugin-installer] Installing ${packageName} ...`);
    const installResult = installOpenclawPlugin(packageName, installEnv);
    if (installResult.alreadyExists) {
      console.log(`[plugin-installer] ${pluginId} already exists, treat as idempotent success.`);
    }
  }

  const updated = loadConfig(configPath);
  applyPluginConfig(updated, pluginId, disableEntries);
  saveConfig(configPath, updated);

  const targetPluginPath = path.join(extensionsDir, pluginDirName);
  if (!fs.existsSync(targetPluginPath)) {
    const actual = pluginDirectoryExists(homeClaw, pluginDirName, extensionsDir);
    console.warn(`[plugin-installer] WARN: expected plugin under ${targetPluginPath}, actual: ${actual.path || 'not found'}`);
  }

  console.log(`[plugin-installer] ${packageName} installed successfully.`);
}

function printHelp() {
  console.log(`Usage:\n  node openclaw-plugin-installer.js install --package <pkg> --id <plugin-id> [options]\n\nOptions:\n  --home <path>              OpenClaw home path (default: /opt/openclaw)\n  --config <path>            OpenClaw config path (required)\n  --state-dir <path>         OpenClaw state dir (default: dirname(--config))\n  --extensions-dir <path>    Plugin install dir (default: <state-dir>/extensions)\n  --plugin-dir <name>        Plugin directory name (default: --id value)\n  --disable-entry <ids>      Comma separated plugin entry ids to disable\n  --force                    Force install even if plugin dir exists\n`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const command = args._[0];

  if (!command || command === 'help' || command === '--help') {
    printHelp();
    process.exit(command ? 0 : 1);
  }

  if (command !== 'install') {
    console.error(`[plugin-installer] Unsupported command: ${command}`);
    printHelp();
    process.exit(1);
  }

  const packageName = args.package;
  const pluginId = args.id;
  const configPath = args.config;
  const homeClaw = args.home || '/opt/openclaw';
  const stateDir = path.resolve(args['state-dir'] || path.dirname(configPath || ''));
  const extensionsDir = path.resolve(args['extensions-dir'] || path.join(stateDir, 'extensions'));
  const pluginDirName = args['plugin-dir'] || pluginId;
  const forceInstall = Boolean(args.force);
  const disableEntries = parseCommaList(args['disable-entry']);

  if (!packageName || !pluginId || !configPath) {
    console.error('[plugin-installer] Missing required args: --package, --id, --config');
    printHelp();
    process.exit(1);
  }

  installPlugin({
    homeClaw,
    configPath,
    packageName,
    pluginId,
    pluginDirName,
    forceInstall,
    stateDir,
    extensionsDir,
    disableEntries
  });
}

main();
