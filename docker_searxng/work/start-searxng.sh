#! /usr/bin/env bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sed -i -e "s/ultrasecretkey/$(openssl rand -hex 16)/g" ${SEARXNG_SETTINGS_PATH:-"/etc/searxng/settings.yml"}

exec python searx/webapp.py $@
