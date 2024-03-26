source /opt/utils/script-utils.sh

setup_lua_base() {
    VERSION_LUA=$(curl -sL https://www.lua.org/download.html | grep "cd lua" | head -1 | grep -Po '(\d[\d|.]+)') \
 && URL_LUA="http://www.lua.org/ftp/lua-${VERSION_LUA}.tar.gz" \
 && echo "Downloading LUA ${VERSION_LUA} from ${URL_LUA}" \
 && install_tar_gz $URL_LUA \
 && mv /opt/lua-* /tmp/lua && cd /tmp/lua \
 && make linux test && make install INSTALL_TOP=/opt/lua \
 && rm -rf /tmp/lua \
 && ln -sf /opt/lua/bin/lua* /usr/bin/ \
 && echo "@ Version of LUA installed: $(lua -v)"
}

setup_lua_rocks() {
 ## https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix
    VERSION_LUA_ROCKS=$(curl -sL https://luarocks.github.io/luarocks/releases/ | grep "linux-x86_64" | head -1 | grep -Po '(\d[\d|.]+)' | head -1) \
 && URL_LUA_ROCKS="http://luarocks.github.io/luarocks/releases/luarocks-${VERSION_LUA_ROCKS}.tar.gz" \
 && echo "Downloading luarocks ${VERSION_LUA_ROCKS} from ${URL_LUA_ROCKS}" \
 && install_tar_gz $URL_LUA_ROCKS \
 && mv /opt/luarocks-* /tmp/luarocks && cd /tmp/luarocks \
 && ./configure --prefix=/opt/lua && make install \
 && rm -rf /tmp/luarocks \
 && ln -sf /opt/lua/bin/lua* /usr/bin/ \
 && echo "@ Version of luarocks: $(luarocks -version)"
}
