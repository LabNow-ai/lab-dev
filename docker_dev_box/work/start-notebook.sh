#!/bin/bash
[ $BASH ] && [ -f /etc/profile  ] && [ -z $ENTER_PROFILE ] && . /etc/profile

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/start--pre.sh

NOTEBOOK_ARGS=""
[ -n "${USE_SSL:+x}" ] && NOTEBOOK_ARGS="${NOTEBOOK_ARGS} --NotebookApp.certfile=${NOTEBOOK_PEM_FILE}"


if [[ ! -z "${JUPYTERHUB_API_TOKEN}" ]]; then
  # launched by JupyterHub, use single-user entrypoint
  exec $DIR/start-singleuser.sh $*
else
  jupyter ${JUPYTER_CMD:-lab} ${NOTEBOOK_ARGS} $*
fi
