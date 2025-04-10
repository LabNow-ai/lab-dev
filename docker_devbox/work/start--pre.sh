#!/bin/bash
set -e

# Generate a SSH id for git if it does not exist.
# [ -e ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -b 4096 -N "" -C `hostname -f` -f ~/.ssh/id_rsa
[ -e ~/.ssh/id_ed25519.pub ] || ssh-keygen -t ed25519 -N "" -C `hostname -f` -f ~/.ssh/id_ed25519

# Generate a self-signed certificate for jupyter if it does not exist (only when GEN_CERT or USE_SSL is set to yes).
JUPYTER_PEM_FILE="/opt/conda/etc/jupyter/certificate.pem"

 ( [ -n "${GEN_CERT:+x}" ] || [ -n "${USE_SSL:+x}" ] ) \
&& [ ! -f ${JUPYTER_PEM_FILE} ] \
&& ( openssl req -new -newkey rsa:2048 \
  -days 356 -nodes -x509 \
  -subj "/C=XX/ST=XX/L=XX/O=generated/CN=generated" \
  -keyout $JUPYTER_PEM_FILE \
  -out $JUPYTER_PEM_FILE \
&& chmod 600 $JUPYTER_PEM_FILE )


# Run hooks, ref: https://github.com/jupyter/docker-stacks/blob/main/images/docker-stacks-foundation/run-hooks.sh
function run_hooks() {
  # The run-hooks.sh script looks for *.sh scripts to source and executable files to run within a passed directory
  if [ "$#" -ne 1 ]; then
    echo "Should pass exactly one directory" && return 1 ;
  fi

  if [[ ! -d "${1}" ]]; then
      echo "Directory ${1} doesn't exist or is not a directory, thus no hooks script executed!" && return 0 ;
  fi

  echo "Running hooks in: ${1} as uid: $(id -u) gid: $(id -g)"
  for f in "${1}/"*; do
      # Handling a case when the directory is empty
      [ -e "${f}" ] || continue
      case "${f}" in
          *.sh)
              echo "Sourcing shell script: ${f}"
              # shellcheck disable=SC1090
              source "${f}"
              # shellcheck disable=SC2181
              if [ $? -ne 0 ]; then
                  echo "${f} has failed, continuing execution"
              fi
              ;;
          *)
              if [ -x "${f}" ]; then
                  echo "Running executable: ${f}"
                  "${f}"
                  # shellcheck disable=SC2181
                  if [ $? -ne 0 ]; then
                      echo "${f} has failed, continuing execution"
                  fi
              else
                  echo "Ignoring non-executable: ${f}"
              fi
              ;;
      esac
  done
  echo "Done running hooks in: ${1}"
}

run_hooks /usr/local/bin/start-jupyter.d
# run-hooks /usr/local/bin/before-jupyter.d

# Print something so running this script returns a non-zero return code
echo "Pre-start work done!"

# ref: https://github.com/jupyter/docker-stacks/blob/main/images/docker-stacks-foundation/start.sh
