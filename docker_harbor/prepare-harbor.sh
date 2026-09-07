#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORK_DIR="${ROOT_DIR}/work"
VERSION="${HARBOR_VERSION:-v2.15.2}"
ARCHIVE="harbor-offline-installer-${VERSION}.tgz"

mkdir -p "${WORK_DIR}/data"
if [[ ! -x "${WORK_DIR}/prepare" || ! -f "${WORK_DIR}/harbor.yml" ]]; then
  command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
  echo "Downloading Harbor ${VERSION} release bundle..."
  curl -fL --retry 3 -o "${WORK_DIR}/${ARCHIVE}" \
    "https://github.com/goharbor/harbor/releases/download/${VERSION}/${ARCHIVE}"
  rm -rf "${WORK_DIR}/bundle"
  mkdir -p "${WORK_DIR}/bundle"
  tar -xzf "${WORK_DIR}/${ARCHIVE}" -C "${WORK_DIR}/bundle" --strip-components=1
  cp "${WORK_DIR}/bundle/prepare" "${WORK_DIR}/prepare"
  chmod +x "${WORK_DIR}/prepare"
  cp "${ROOT_DIR}/harbor.yml.tmpl" "${WORK_DIR}/harbor.yml"
  sed -i \
    -e "s/^hostname: reg.mydomain.com/hostname: ${HARBOR_HOSTNAME:-harbor.localhost}/" \
    -e "s/^  port: 80/  port: ${HARBOR_GENERATOR_HTTP_PORT:-8080}/" \
    -e "s|^data_volume: /data|data_volume: ${WORK_DIR}/data|" \
    "${WORK_DIR}/harbor.yml"
  if [[ -z "${HARBOR_ADMIN_PASSWORD:-}" ]]; then
    echo "Set HARBOR_ADMIN_PASSWORD and run this script again before starting Harbor." >&2
    exit 1
  fi
  sed -i "s/^harbor_admin_password: .*/harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}/" "${WORK_DIR}/harbor.yml"
fi

# The official prepare binary creates the version-matched common/config tree and
# all runtime keys/certificates. The checked-in Compose file is the stable entrypoint.
HARBOR_BUNDLE_DIR="${WORK_DIR}" "${WORK_DIR}/prepare" "${WORK_DIR}/harbor.yml"

echo "Harbor configuration is ready. Start it with:"
echo "  cd ${ROOT_DIR}/compose"
echo "  docker compose --env-file .env -f docker-compose.harbor.yml up -d"
