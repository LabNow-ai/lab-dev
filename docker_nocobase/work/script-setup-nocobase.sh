setup_nocobase_create_app(){
 ## ref: https://github.com/nocobase/nocobase/blob/main/docker/nocobase/Dockerfile-full
    local VER_NOCO=${1:-"latest"} \
 && npx -y create-nocobase-app@${VER_NOCO} nocobase --empty-key --skip-dev-dependencies -a -e APP_ENV=production \
 && cd nocobase \
 && yarn install --production \
 && rm -rf yarn.lock \
 && find node_modules -type f -name "yarn.lock"     -delete \
 && find node_modules -type f -name "bower.json"    -delete \
 && find node_modules -type f -name "composer.json" -delete \
 && find node_modules -type d -name docs ! -path "node_modules/@nocobase/*" -prune -exec rm -rf '{}' + \
 && find node_modules -type f -name "*.map" -delete \
 && find node_modules -type f -name "*.md" ! -path "node_modules/@nocobase/*" -delete ;
}

setup_nocobase_from_source(){
    local BRANCH_NOCO=${1:-"origin/main"} \
 && cd /opt/nocobase \
 && git config --global --add safe.directory /opt/nocobase \
 && git init && git remote add origin https://github.com/nocobase/nocobase \
 && git fetch && git checkout -t $BRANCH_NOCO \
 && yarn install --frozen-lockfile && yarn run build --not-dts ;
}
