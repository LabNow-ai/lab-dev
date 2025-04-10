#!/bin/sh
# vim:sw=2:ts=2:sts=2:et

set -eu

# Check if the environment variable PROFILE_LOCALIZE is set and not empty
if [ -z "${PROFILE_LOCALIZE+x}" ]; then
  echo "No action taken as PROFILE_LOCALIZE is not set or is empty." ;
else
  /bin/sh /opt/utils/script-localize.sh ;
fi
