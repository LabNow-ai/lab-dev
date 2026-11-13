#!/bin/sh
# vim:sw=2:ts=2:sts=2:et

set -eu

LC_ALL=C
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ME=$(basename "$0")

DIR_PROFILE="${PROFILE_DIR_NGINX:-/etc/nginx/profiles}"
DIR_SOURCE="${DIR_TEMPLATE_SOURCE:-/etc/nginx/templates.repo}"
DIR_TARGET="${NGINX_ENVSUBST_TEMPLATE_DIR:-/etc/nginx/templates}"
PROFILE="${PROFILE_NGINX:-}"

entrypoint_log() {
    if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

# when profile is not set, skip template preparation
if [ -z "$PROFILE" ]; then
    entrypoint_log "$ME: PROFILE_NGINX not set, skipping template preparation"
    exit 0
fi

case "$PROFILE" in
    *[!a-zA-Z0-9._-]*)
        entrypoint_log "$ME: invalid PROFILE_NGINX '$PROFILE', skipping"
        exit 0
        ;;
esac

FILE_PROFILE="${DIR_PROFILE}/${PROFILE}.list"

if [ ! -f "$FILE_PROFILE" ]; then
    entrypoint_log "$ME: profile file not found: $FILE_PROFILE, skipping"
    exit 0
fi

if [ ! -d "$DIR_SOURCE" ]; then
    entrypoint_log "$ME: template source dir not found: $DIR_SOURCE, skipping"
    exit 0
fi

mkdir -p "$DIR_TARGET"
find "$DIR_TARGET" -mindepth 1 -maxdepth 1 -type f -delete

entrypoint_log "$ME: preparing templates for profile '$PROFILE'"

count=0
while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    line="${line%%#*}"  # remove comments
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -z "$line" ]; then
        continue
    fi

    case "$line" in
        *.conf.template|*.conf.stream-template) ;;
        *)
            entrypoint_log "$ME: skipping invalid template name: $line"
            continue
            ;;
    esac

    case "$line" in
        */*|*..*)
            entrypoint_log "$ME: skipping invalid template path: $line"
            continue
            ;;
    esac

    src="${DIR_SOURCE}/${line}"
    if [ ! -f "$src" ]; then
        entrypoint_log "$ME: skipping missing template: $src"
        continue
    fi

    cp "$src" "${DIR_TARGET}/${line}"
    count=$((count + 1))
done < "$FILE_PROFILE"

entrypoint_log "$ME: prepared $count template(s)"
exit 0
