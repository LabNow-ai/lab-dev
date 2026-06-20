#!/usr/bin/env bash
# Generate /etc/supervisord.conf dynamically and run supervisord
set -eu

# Set up dashboard parameters
dash_host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
dash_port="${HERMES_DASHBOARD_PORT:-9119}"

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
command=exec hermes gateway run --replace
directory=/opt/data
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:dashboard]
command=exec hermes dashboard --host ${dash_host} --port ${dash_port} --no-open ${insecure}
directory=/opt/data
autostart=${dashboard_autostart}
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EOF

echo "[start-hermes] Starting supervisord..."
exec supervisord -c /etc/supervisord.conf
