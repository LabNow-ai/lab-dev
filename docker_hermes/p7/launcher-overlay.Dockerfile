# syntax=docker/dockerfile:1

ARG P6_LAUNCHER_IMAGE
FROM ${P6_LAUNCHER_IMAGE}

ARG LAUNCHER_SOURCE_COMMIT
ARG P6_LAUNCHER_IMAGE
ARG P6_LAUNCHER_BASE_DIGEST
LABEL org.opencontainers.image.revision="${LAUNCHER_SOURCE_COMMIT}" \
      io.labnow.p7.launcher-base="${P6_LAUNCHER_BASE_DIGEST}" \
      io.labnow.p7.delivery="local-only-overlay"

# P7 only changes the Launcher runtime consumer and its Hub-trusted config.
# The named build context must be the clean, fixed Launcher Phase checkout.
COPY --from=launcher src/labnow-launcher/devhub_launcher /opt/jupyterhub/devhub_launcher
COPY --from=launcher src/labnow-launcher/resource/config/app.conf /opt/jupyterhub/resource/config/app.conf
