#!/bin/sh
set -eu

STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
CONFIG_PATH="${STATE_DIR}/openclaw.json"
TEMPLATE_PATH="${OPENCLAW_CONFIG_TEMPLATE:-/opt/openclaw/openclaw.template.json}"
PLUGIN_DIR="${STATE_DIR}/extensions/openclaw-lark"

ensure_config_file() {
  mkdir -p "${STATE_DIR}"

  if [ ! -s "${CONFIG_PATH}" ]; then
    if [ -f "${TEMPLATE_PATH}" ]; then
      cp "${TEMPLATE_PATH}" "${CONFIG_PATH}"
    else
      cat >"${CONFIG_PATH}" <<'JSON'
{
  "agents": {
    "defaults": {
      "workspace": "/home/node/.openclaw/workspace"
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
const p = process.env.CONFIG_PATH;
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
const p = process.env.CONFIG_PATH;
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
  export CONFIG_PATH
  ensure_config_file

  if [ ! -d "${PLUGIN_DIR}" ]; then
    echo "[bootstrap] openclaw-lark not found, installing..."
    remove_uninstalled_plugin_refs
    node openclaw.mjs plugins install @larksuite/openclaw-lark
    enable_feishu_plugin
    echo "[bootstrap] openclaw-lark installation completed."
  fi
}

bootstrap
exec node openclaw.mjs "$@"