#!/bin/bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/start--pre.sh

JUPYTER_ARGS=""
[ -n "${USE_SSL:+x}" ] && JUPYTER_ARGS="${JUPYTER_ARGS:-""} --NotebookApp.certfile=${JUPYTER_PEM_FILE}"


if [[ ! -z "${JUPYTERHUB_API_TOKEN}" ]]; then
  # launched by JupyterHub, use single-user entrypoint
  exec $DIR/start-singleuser.sh $*
else
  jupyter ${JUPYTER_CMD:-lab} ${JUPYTER_ARGS} $*
fi
