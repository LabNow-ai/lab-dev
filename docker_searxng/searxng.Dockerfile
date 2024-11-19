# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /tmp/searxng

RUN set -eux \
&& pip install -U pyyaml uwsgi \
&& git clone https://github.com/searxng/searxng /opt/searxng/ \
&& cd /opt/searxng && pip install --use-pep517 --no-build-isolation -e . \
&& mv /tmp/searxng/* /opt/searxng && ln -sf /opt/searxng/etc /etc/searxng \
&& chmod +x /opt/searxng/*.sh \
# ----------------------------- Install supervisord
&& source /opt/utils/script-setup-sys.sh && setup_supervisord \
# ----------------------------- Install caddy
&& source /opt/utils/script-setup-net.sh && setup_caddy \
# Clean up and display components version information...
&& list_installed_packages && install__clean

ENV SEARXNG_HOSTNAME="http://localhost:80"
ENV SEARXNG_TLS=internal

ENV SEARXNG_SETTINGS_PATH="/etc/searxng/settings.yml"
ENV SEARXNG_BASE_URL=https://${SEARXNG_HOSTNAME:-localhost}/
ENV UWSGI_WORKERS=4
ENV UWSGI_THREADS=4

ENTRYPOINT ["tini", "-g", "--"]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
WORKDIR /opt/searxng
CMD ["start-supervisord.sh"]
EXPOSE 8888
