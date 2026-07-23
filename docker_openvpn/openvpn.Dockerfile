# Distributed under the terms of the Modified BSD License.

# Using kylemanna/openvpn as the base image as recommended in the article
FROM kylemanna/openvpn:2.4

# Maintain standard LabNow metadata or labels if needed
LABEL maintainer="LabNow Team"

# The base image already has the necessary entrypoint and scripts.
# We can add custom initialization scripts here if needed, 
# similar to how docker_clash does it.

# Install additional utilities for debugging and management
RUN apk add --no-cache curl bash jq iproute2

# Expose the default OpenVPN port
EXPOSE 1194/udp

# Healthcheck to verify if OpenVPN is running (checking for the process)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD pgrep openvpn || exit 1
