setup_nocobase_create_app(){
 ## ref: https://github.com/nocobase/nocobase/blob/main/docker/nocobase/Dockerfile-full
    local VER_NOCO=${1:-"latest"} \
 && npx -y create-nocobase-app@${VER_NOCO} nocobase --empty-key --skip-dev-dependencies -a -e APP_ENV=production \
 && cd nocobase \
 && yarn install --production \
 && rm -rf yarn.lock ;
}

setup_nocobase_from_source(){
    local BRANCH_NOCO=${1:-"origin/main"} \
 && cd /opt/nocobase \
 && git config --global --add safe.directory /opt/nocobase \
 && git init && git remote add origin https://github.com/nocobase/nocobase \
 && git fetch && git checkout -t $BRANCH_NOCO \
 && yarn install --frozen-lockfile && yarn run build --not-dts ;
}
