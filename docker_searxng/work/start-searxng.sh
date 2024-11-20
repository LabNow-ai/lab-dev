#! /usr/bin/env bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export SEARXNG_SECRET=$(openssl rand -hex 16)
sed -i -e "s/ultrasecretkey/${SEARXNG_SECRET}/g" ${SEARXNG_SETTINGS_PATH:-"/etc/searxng/settings.yml"}

git config --global --add safe.directory /opt/searxng ;
cp -rf ~/.gitconfig /opt/searxng/ || true ;

# exec python searx/webapp.py $@
source /opt/searxng/dockerfiles/docker-entrypoint.sh
