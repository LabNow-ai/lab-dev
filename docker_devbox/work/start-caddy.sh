#!/bin/bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

URL_PREFIX=${JUPYTERHUB_SERVICE_PREFIX:-"/"} exec /usr/local/bin/caddy run --config  /etc/caddy/Caddyfile
