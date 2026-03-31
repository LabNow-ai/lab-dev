#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

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

function pluginDirectoryExists(homeClaw, pluginDirName) {
  const pluginPath = path.join(homeClaw, 'extensions', pluginDirName);
  return fs.existsSync(pluginPath);
}

function installOpenclawPlugin(packageName) {
  execFileSync('openclaw', ['plugins', 'install', packageName], {
    stdio: 'inherit'
  });
}

function cleanupFeishuLarkRefs(config) {
  ensureConfigShape(config);
  config.plugins.allow = config.plugins.allow.filter((id) => id !== 'openclaw-lark');
  delete config.plugins.entries['openclaw-lark'];

  if (!config.plugins.entries.feishu) {
    config.plugins.entries.feishu = { enabled: false };
  } else {
    config.plugins.entries.feishu.enabled = false;
  }
}

function applyFeishuLarkConfig(config) {
  if (!config.channels) config.channels = {};
  if (!config.channels.feishu) {
    config.channels.feishu = {
      enabled: true,
      appId: '',
      appSecret: '',
      domain: 'feishu',
      connectionMode: 'websocket',
      requireMention: true,
      dmPolicy: 'pairing',
      groupPolicy: 'open',
      allowFrom: [],
      groupAllowFrom: []
    };
  }

  ensureConfigShape(config);

  if (!config.plugins.allow.includes('openclaw-lark')) {
    config.plugins.allow.push('openclaw-lark');
  }

  config.plugins.entries.feishu = { enabled: false };
  config.plugins.entries['openclaw-lark'] = { enabled: true };
}

function installPlugin(options) {
  const {
    homeClaw,
    configPath,
    packageName,
    pluginId,
    pluginDirName,
    forceInstall,
    profile
  } = options;

  const exists = pluginDirectoryExists(homeClaw, pluginDirName);
  if (exists && !forceInstall) {
    console.log(`[plugin-installer] ${pluginId} already exists at extensions/${pluginDirName}, skip install.`);
    return;
  }

  const config = loadConfig(configPath);

  if (profile === 'feishu-lark') {
    cleanupFeishuLarkRefs(config);
    saveConfig(configPath, config);
  }

  console.log(`[plugin-installer] Installing ${packageName} ...`);
  installOpenclawPlugin(packageName);

  const updated = loadConfig(configPath);
  if (profile === 'feishu-lark') {
    applyFeishuLarkConfig(updated);
  }
  saveConfig(configPath, updated);

  console.log(`[plugin-installer] ${packageName} installed successfully.`);
}

function printHelp() {
  console.log(`Usage:\n  node openclaw-plugin-installer.js install --package <pkg> --id <plugin-id> [options]\n\nOptions:\n  --home <path>           OpenClaw home path (default: /opt/openclaw)\n  --config <path>         OpenClaw config path (required)\n  --plugin-dir <name>     Plugin directory name under extensions/ (default: --id value)\n  --profile <name>        Optional profile (supported: feishu-lark)\n  --force                 Force install even if plugin dir exists\n`);
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
  const pluginDirName = args['plugin-dir'] || pluginId;
  const forceInstall = Boolean(args.force);
  const profile = args.profile || '';

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
    profile
  });
}

main();
