# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"


# Stage 1: build code, both backend and frontend
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} as builder
COPY work /opt/utils/
RUN set -eux \
 && source /opt/utils/script-setup-casdoor.sh \
 && setup_casdoor


# Stage 2: runtime image, copy files from builder image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}
COPY --from=builder /opt/casdoor /opt/casdoor
COPY work/app.conf /opt/casdoor/conf/app.conf
RUN set -eux \
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends lsof \
 && mkdir -pv /root/web && ln -sf /opt/casdoor/web/build /root/web/ && ls -alh /opt/casdoor/web \
 && chmod +x /opt/casdoor/docker-entrypoint.sh \
 && ln -sf /opt/casdoor/server /server \
 && ln -sf /opt/casdoor/conf   /conf \
 && ls -alh /opt/casdoor \
 && echo "@ Version of Casdoor $(cat /opt/casdoor/version_info.txt)"

LABEL maintainer="postmaster@labnow.ai"
ENV RUNNING_IN_DOCKER=true
WORKDIR /opt/casdoor
# 8000=web, 389=ldap, 1812=radius
EXPOSE 8000 389 1812
ENTRYPOINT ["/bin/bash"]
CMD ["/opt/casdoor/docker-entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["curl", "--head", "-fsSk", "http://localhost:8000/health/ready"]
