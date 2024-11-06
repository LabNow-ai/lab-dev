#! /usr/bin/env bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"



if [[ "$RSTUDIO_ARGS $@" != *"--www-port="* ]]; then
  RSTUDIO_ARGS="--www-port=8787 $RSTUDIO_ARGS"
fi


USER=root /opt/rstudio-server/bin/rserver ${RSTUDIO_ARGS} $@
