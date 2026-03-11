#! /usr/bin/env bash

# run scripts in storage/scripts
if [ -d "/opt/nocobase/storage/scripts" ]; then
  for f in /opt/nocobase/storage/scripts/*.sh; do
    [ -e "$f" ] || continue
    echo "Running $f"
    sh "$f"
  done
fi

source /etc/profile.d/path-*.sh

cd /opt/nocobase && yarn nocobase install --lang=${LOCALE:-"zh-CN"} && yarn start --quickstart
