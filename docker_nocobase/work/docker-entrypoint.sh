#! /usr/bin/env bash

# run scripts in storage/scripts
if [ -d "/opt/nocobase/storage/scripts" ]; then
  for f in /opt/nocobase/storage/scripts/*.sh; do
    [ -e "$f" ] || continue
    echo "Running $f"
    sh "$f"
  done
fi

cd /opt/nocobase && yarn start --quickstart
