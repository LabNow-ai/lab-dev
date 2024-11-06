#!/bin/bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/start--pre.sh

# ref: https://github.com/jupyter/docker-stacks/blob/main/images/base-notebook/start-singleuser.py

if [[ "$JUPYTER_ARGS $@" != *"--ip="* ]]; then
  JUPYTER_ARGS="--ip=0.0.0.0 $JUPYTER_ARGS"
fi


# handle some deprecated environment variables from DockerSpawner < 0.8.
# These won't be passed from DockerSpawner 0.9, so avoid specifying --arg=empty-string
if [ ! -z "$NOTEBOOK_DIR" ]; then
  JUPYTER_ARGS="--notebook-dir='$NOTEBOOK_DIR' $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_PORT" ]; then
  JUPYTER_ARGS="--port=$JPY_PORT $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_USER" ]; then
  JUPYTER_ARGS="--user=$JPY_USER $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_COOKIE_NAME" ]; then
  JUPYTER_ARGS="--cookie-name=$JPY_COOKIE_NAME $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_BASE_URL" ]; then
  JUPYTER_ARGS="--base-url=$JPY_BASE_URL $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_HUB_PREFIX" ]; then
  JUPYTER_ARGS="--hub-prefix=$JPY_HUB_PREFIX $JUPYTER_ARGS"
fi
if [ ! -z "$JPY_HUB_API_URL" ]; then
  JUPYTER_ARGS="--hub-api-url=$JPY_HUB_API_URL $JUPYTER_ARGS"
fi

exec jupyterhub-singleuser ${JUPYTER_ARGS} $@
