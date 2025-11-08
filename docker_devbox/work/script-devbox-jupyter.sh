source /opt/utils/script-utils.sh


setup_jupyter_base() {
  pip install -Uq --pre jupyterlab notebook ipywidgets jupyter-server-proxy jupyterhub
  
  type jupyter || return -1 ;

  # commnad `jupyterhub-singleuser` is provided by jupterhub and will be used by dockerspawner
  type jupyterhub-singleuser || return -1;

  echo "@ Version of Jupyter Server: $(jupyter server --version)"
  echo "@ Version of Jupyter Lab: $(jupyter lab --version)"
  echo "@ Version of Jupyter Notebook: $(jupyter notebook --version)"

  jupyter labextension disable "@jupyterlab/apputils-extension:announcements"
}


setup_jupyter_kernels() {
     echo "@ Jupyter Kernels RefList: https://github.com/jupyter/jupyter/wiki/Jupyter-kernels"

     echo "@ Install Jupyter Kernel for Bash" \
  && pip install -Uq bash_kernel && python -m bash_kernel.install --sys-prefix

  ## checked @ 2024-0307
     which npm \
  && echo "@ Install Jupyter Kernel for JavaScript/TypeScript: https://github.com/yunabe/tslab" \
  && npm install -g tslab \
  && tslab install --sys-prefix --python /opt/conda/bin/python --binary $(which tslab)
  ## ref: https://github.com/n-riesco/ijavascript (#TODO: not working for now)
  # && npm_config_zmq_external=true npm install -g --unsafe-perm ijavascript \
  # && /opt/node/bin/ijsinstall --install=global --spec-path=full \
  # && mv /usr/local/share/jupyter/kernels/javascript /opt/conda/share/jupyter/kernels/

  ## alternative: https://github.com/jupyter-xeus/xeus-r
  ## alternative: https://github.com/melff/RKernel
  ## checked @ 2024-0307  # TODO: help func requries proxy
     which R \
  && echo "@ Install Jupyter Kernel for R:" \
  && R -e "install.packages('IRkernel')" \
  && R -e "IRkernel::installspec(user=FALSE)" \
  && mv /usr/local/share/jupyter/kernels/*r* /opt/conda/share/jupyter/kernels/

  ## checked @ 2024-0307
     which go \
  && echo "@ Install Jupyter Kernel for Golang: https://github.com/janpfeifer/gonb" \
  && export GOPATH=/opt/go/path \
  && go install github.com/janpfeifer/gonb@latest \
  && go install golang.org/x/tools/cmd/goimports@latest \
  && go install golang.org/x/tools/gopls@latest \
  && $GOPATH/bin/gonb --install \
  && mv ~/.local/share/jupyter/kernels/gonb /opt/conda/share/jupyter/kernels/

  ## checked @ 2024-0614
  # alternative approaches to install evxcr_jupyter:
  # && cargo install --locked evcxr_jupyter \
     which rustc \
  && echo "@ Install Jupyter Kernel for Rust: https://github.com/evcxr/evcxr/blob/main/evcxr_jupyter/README.md" \
  && VER_EVCXR=$(curl -sL https://github.com/evcxr/evcxr/releases.atom | grep 'releases/tag' | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_EVCXR="https://github.com/evcxr/evcxr/releases/download/v${VER_EVCXR}/evcxr_jupyter-v${VER_EVCXR}-x86_64-unknown-linux-gnu.tar.gz" \
  && echo "Downloading evcxr version ${VER_EVCXR} from: ${URL_EVCXR}" \
  && install_tar_gz $URL_EVCXR && mv /opt/evcxr* /tmp/evcxr && mv /tmp/evcxr/evcxr_jupyter /opt/cargo/bin/ \
  && /opt/cargo/bin/evcxr_jupyter --install --sys-prefix \
  && mv ~/.local/share/jupyter/kernels/rust /opt/conda/share/jupyter/kernels/

  ## checked @ 2024-0307
     which julia \
  && echo "@ Install Jupyter Kernel for Julia: https://github.com/JuliaLang/IJulia.jl" \
  && julia -e "using Pkg; Pkg.add(\"IJulia\"); Pkg.precompile();"
  ( mv ~/.local/share/jupyter/kernels/julia* /opt/conda/share/jupyter/kernels/ || true );

  ## Checked @ 2024-0614
     which java \
  && export JBANG_DIR=/opt/jbang && export PATH=${PATH}:${JBANG_DIR}/bin \
  && echo "export JBANG_DIR=${JBANG_DIR}"         > /etc/profile.d/path-jbang.sh \
  && echo 'export PATH=${PATH}:${JBANG_DIR}/bin' >> /etc/profile.d/path-jbang.sh \
  && curl -Ls https://sh.jbang.dev | bash -s - app setup \
  && ${JBANG_DIR}/bin/jbang trust add https://github.com/jupyter-java \
  && ${JBANG_DIR}/bin/jbang install-kernel@jupyter-java \
  && mv ~/.local/share/jupyter/kernels/jbang-* /opt/conda/share/jupyter/kernels/

  ## https://github.com/jupyter-xeus/xeus-octave  # TODO: to check
     which octave \
  && export PATH=/opt/octave/bin:$PATH \
  && pip install -Uq xeus-python

  echo "@ Installed Jupyter Kernels:" && jupyter kernelspec list
}


setup_jupyter_extensions() {
     install_apt /opt/utils/install_list_JPY_extend.apt \
  && install_pip /opt/utils/install_list_JPY_extend.pip

     echo "@ Jupyter Server Extension list: "   && jupyter server extension list \
  && echo "@ Jupyter Lab Extension list: "      && jupyter labextension list \
  && echo "@ Jupyter Notebook Extension list: " && jupyter notebook extension list
}


setup_jupyter_hub() {  
   # ref1: https://github.com/jupyterhub/jupyterhub
   # ref2: https://github.com/jupyterhub/jupyterhub/blob/main/Dockerfile
   # ref3: https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/main/images/hub/unfrozen/requirements.txt
   which npm && ( npm install -g npm configurable-http-proxy ) || ( echo "NPM not found!" && return 255 )

   pip install -Uq --pre jupyterhub jupyter_client \
      dockerspawner jupyterhub-kubespawner jupyterhub-systemdspawner wrapspawner \
      jupyterhub-ldapauthenticator jupyterhub-kerberosauthenticator \
      jupyterhub-firstuseauthenticator jupyterhub-hmacauthenticator jupyterhub-ltiauthenticator \
      jupyterhub-nativeauthenticator jupyterhub-tmpauthenticator \
      oauthenticator[googlegroups,mediawiki] jupyterhub-idle-culler \
      psycopg pymysql sqlalchemy-cockroachdb \
      psutil pycurl py-spy \
      jupyterhub-traefik-proxy configurable-http-proxy

   type jupyterhub && echo "@ JupyterHub version: $(jupyterhub --version)" || return -1 ;
}
