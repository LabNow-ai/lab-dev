source /opt/utils/script-utils.sh


setup_jupyter_base() {
     pip install -Uq --pre jupyterhub jupyterlab notebook ipywidgets jupyter-server-proxy \
  && echo "@ Version of Jupyter Server: $(jupyter server --version)" \
  && echo "@ Version of Jupyter Lab: $(jupyter lab --version)" \
  && echo "@ Version of Jupyter Notebook: $(jupyter notebook --version)" \
  && echo "@ Version of JupyterHub: $(jupyterhub --version)"
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

  ## checked @ 2024-0307  # TODO: help func requries proxy
     which R \
  && echo "@ Install Jupyter Kernel for R: https://github.com/melff/RKernel" \
  && R -e "devtools::install_github('melff/RKernel/pkg')" \
  && R -e "RKernel::installspec(user=FALSE)" \
  && mv /usr/local/share/jupyter/kernels/rkernel /opt/conda/share/jupyter/kernels/

  ## checked @ 2024-0307
     which go \
  && echo "@ Install Jupyter Kernel for Golang: https://github.com/janpfeifer/gonb" \
  && export GOPATH=/opt/go/path \
  && go install github.com/janpfeifer/gonb@latest \
  && go install golang.org/x/tools/cmd/goimports@latest \
  && go install golang.org/x/tools/gopls@latest \
  && $GOPATH/bin/gonb --install \
  && mv ~/.local/share/jupyter/kernels/gonb /opt/conda/share/jupyter/kernels/

  ## TODO: buggy, cargo install sccache
     which rustc \
  && echo "@ Install Jupyter Kernel for Rust: https://github.com/evcxr/evcxr/issues/140" \
  && cargo install --locked evcxr_jupyter \
  && evcxr_jupyter --install --sys-prefix \
  && mv ~/.local/share/jupyter/kernels/rust /opt/conda/share/jupyter/kernels/

  ## TODO: buggy
     which java \
  && pip install -Uq pandas py4j
  #&& pip install beakerx && beakerx install \
  #&& jupyter labextension install beakerx-jupyterlab

  ## checked @ 2024-0307
     which julia \
  && echo "@ Install Jupyter Kernel for Julia: https://github.com/JuliaLang/IJulia.jl" \
  && julia -e "using Pkg; Pkg.add(\"IJulia\"); Pkg.precompile();" \
  && mv ~/.local/share/jupyter/kernels/julia* /opt/conda/share/jupyter/kernels/

  ## https://github.com/jupyter-xeus/xeus-octave  # TODO: to check
     which octave \
  && export PATH=/opt/octave/bin:$PATH \
  && pip install -Uq xeus-python

  echo "@ Installed Jupyter Kernels:" && jupyter kernelspec list
}


setup_jupyter_extensions() {
     install_apt /opt/utils/install_list_JPY_extend.apt \
  && install_pip /opt/utils/install_list_JPY_extend.pip

     echo "@ Jupyter Server Extension list: " && jupyter server extension list \
  && echo "@ Jupyter Lab Extension list: " && jupyter labextension list \
  && echo "@ Jupyter Notebook Extension list: " && jupyter notebook extension list
}
