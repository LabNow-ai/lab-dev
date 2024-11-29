#!/bin/sh
# vim:sw=2:ts=2:sts=2:et

set -eu

PROFILE_LOCALIZE=${PROFILE_LOCALIZE:-"default"} ;
echo "PROFILE_LOCALIZE=${PROFILE_LOCALIZE}" ;

# Check if the environment variable PROFILE_LOCALIZE is set and not empty
if [ -n "$PROFILE_LOCALIZE" ]; then
  /bin/sh /opt/utils/script-localize.sh ;
else
  echo "No action taken as PROFILE_LOCALIZE is not set or is empty." ;
fi
