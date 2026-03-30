#!/bin/sh
set -eu

DIR_STATE="${OPENCLAW_DIR_STATE:-/opt/openclaw/data}"
DIR_PLUGIN="${DIR_STATE}/extensions/openclaw-lark"
PATH_CONFIG="${DIR_STATE}/openclaw.json"
PATH_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-/opt/openclaw/openclaw.template.json}"


ensure_config_file() {
  mkdir -p "${DIR_STATE}"

  if [ ! -s "${PATH_CONFIG}" ]; then
    if [ -f "${PATH_TEMPLATE}" ]; then
      cp "${PATH_TEMPLATE}" "${PATH_CONFIG}"
    else
      cat >"${PATH_CONFIG}" <<'JSON'
{
  "agents": {
    "defaults": {
      "workspace": "/opt/openclaw/data/workspace"
    }
  },
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
JSON
    fi
  fi
}

remove_uninstalled_plugin_refs() {
  node <<'NODE'
const fs = require('fs');
const p = process.env.PATH_CONFIG;
const raw = fs.readFileSync(p, 'utf8');
const c = JSON.parse(raw);

if (!c.plugins) c.plugins = {};
if (!c.plugins.entries) c.plugins.entries = {};

if (Array.isArray(c.plugins.allow)) {
  c.plugins.allow = c.plugins.allow.filter((id) => id !== 'openclaw-lark');
}
if (c.plugins.entries['openclaw-lark']) {
  delete c.plugins.entries['openclaw-lark'];
}
if (!c.plugins.entries.feishu) {
  c.plugins.entries.feishu = { enabled: false };
} else {
  c.plugins.entries.feishu.enabled = false;
}

fs.writeFileSync(p, JSON.stringify(c, null, 2));
NODE
}

enable_feishu_plugin() {
  node <<'NODE'
const fs = require('fs');
const p = process.env.PATH_CONFIG;
const raw = fs.readFileSync(p, 'utf8');
const c = JSON.parse(raw);

if (!c.channels) c.channels = {};
if (!c.channels.feishu) {
  c.channels.feishu = {
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

if (!c.plugins) c.plugins = {};
if (!Array.isArray(c.plugins.allow)) c.plugins.allow = [];
if (!c.plugins.allow.includes('openclaw-lark')) c.plugins.allow.push('openclaw-lark');
if (!c.plugins.entries) c.plugins.entries = {};
c.plugins.entries.feishu = { enabled: false };
c.plugins.entries['openclaw-lark'] = { enabled: true };

fs.writeFileSync(p, JSON.stringify(c, null, 2));
NODE
}

bootstrap() {
  export PATH_CONFIG
  ensure_config_file

  if [ ! -d "${DIR_PLUGIN}" ]; then
    echo "[bootstrap] openclaw-lark not found, installing..."
    remove_uninstalled_plugin_refs
    openclaw plugins install @larksuite/openclaw-lark
    enable_feishu_plugin
    echo "[bootstrap] openclaw-lark installation completed."
  fi
}

bootstrap
exec openclaw "$@"
