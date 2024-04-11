source /opt/utils/script-utils.sh

export LUA_HOME=/opt/lua

setup_lua_base() {
    VERSION_LUA=$(curl -sL https://www.lua.org/download.html | grep "cd lua" | head -1 | grep -Po '(\d[\d|.]+)') \
 && URL_LUA="http://www.lua.org/ftp/lua-${VERSION_LUA}.tar.gz" \
 && echo "Downloading LUA ${VERSION_LUA} from ${URL_LUA}" \
 && install_tar_gz $URL_LUA \
 && mv /opt/lua-* /tmp/lua && cd /tmp/lua \
 && make linux test && make install INSTALL_TOP=${LUA_HOME} \
 && ln -sf ${LUA_HOME}/bin/lua* /usr/bin/ \
 && rm -rf /tmp/lua \
 && echo "@ Version of LUA installed: $(lua -v)"
}

setup_lua_rocks() {
 ## https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix
    VERSION_LUA_ROCKS=$(curl -sL https://luarocks.github.io/luarocks/releases/ | grep "linux-x86_64" | head -1 | grep -Po '(\d[\d|.]+)' | head -1) \
 && URL_LUA_ROCKS="http://luarocks.github.io/luarocks/releases/luarocks-${VERSION_LUA_ROCKS}.tar.gz" \
 && echo "Downloading luarocks ${VERSION_LUA_ROCKS} from ${URL_LUA_ROCKS}" \
 && install_tar_gz $URL_LUA_ROCKS \
 && mv /opt/luarocks-* /tmp/luarocks && cd /tmp/luarocks \
 && ./configure --prefix=${LUA_HOME} --with-lua-include=${LUA_HOME}/include && make install \
 && ln -sf /opt/lua/bin/lua* /usr/bin/ \
 && rm -rf /tmp/luarocks \
 && echo "@ Version of luarocks: $(luarocks --version)"
}
