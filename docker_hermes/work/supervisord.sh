#!/usr/bin/env bash
# Generate /etc/supervisord.conf dynamically and run supervisord.
# This is the standalone `start-hermes.sh all` compatibility path. Workspace
# wrappers should manage gateway/dashboard directly through their own supervisor.
set -eu

# Set up dashboard parameters
dash_host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
dash_port="${HERMES_DASHBOARD_PORT:-9119}"
hermes_home="${HERMES_HOME:-/root/workspace}"

insecure=""
case "${HERMES_DASHBOARD_INSECURE:-}" in
    1|true|TRUE|True|yes|YES|Yes) insecure="--insecure" ;;
esac

dashboard_autostart="false"
case "${HERMES_DASHBOARD:-}" in
    1|true|TRUE|True|yes|YES|Yes) dashboard_autostart="true" ;;
esac

# Generate /etc/supervisord.conf
cat <<EOF > /etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:gateway]
command=hermes gateway run --replace
directory=${hermes_home}
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:dashboard]
command=hermes dashboard --host ${dash_host} --port ${dash_port} --no-open ${insecure}
directory=${hermes_home}
autostart=${dashboard_autostart}
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EOF

echo "[start-hermes] Starting supervisord..."
exec supervisord -c /etc/supervisord.conf
