#! /usr/bin/env bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"



if [[ "$CODER_ARGS $@" != *"--bind-addr="* ]]; then
  CODER_ARGS="--bind-addr=0.0.0.0:9999 $CODER_ARGS"
fi


exec /opt/code-server/bin/code-server --auth=none --disable-telemetry --disable-update-check ${CODER_ARGS} $@ /root
