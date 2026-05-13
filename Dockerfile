# syntax=docker/dockerfile:1.7
FROM debian:stable-slim

LABEL org.opencontainers.image.title="Grand Theft Auto Connected Server"
LABEL org.opencontainers.image.description="Grand Theft Auto Connected (GTA IV multiplayer) dedicated server, packaged for Docker. Auto-fetches the latest server build on every boot."
LABEL org.opencontainers.image.source="https://github.com/MightyRufo/gtac-server"
LABEL org.opencontainers.image.licenses="MIT"

ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl tar gzip tini tzdata libstdc++6 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd -g 1000 gtac \
 && useradd  -u 1000 -g 1000 -m -d /home/gtac -s /usr/sbin/nologin gtac \
 && mkdir -p /opt/gtac /config /data/logs \
 && chown -R gtac:gtac /opt/gtac /config /data

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Default download host. Override only if mirroring.
ENV GTAC_DOWNLOADS_URL="https://gtaconnected.com/downloads/"

# Pin a specific version (e.g. "1.7.3") or leave empty to auto-pick latest
# from GTAC_DOWNLOADS_URL on every container start.
ENV GTAC_VERSION=""

# Architecture override. Auto-detected when empty. Valid: "AMD64" or "ARM64".
ENV GTAC_ARCH=""

# Set "1" to skip the update check (useful for offline / air-gapped runs once
# /opt/gtac is populated).
ENV GTAC_SKIP_UPDATE="0"

EXPOSE 22000/tcp 22000/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sS -o /dev/null -m 4 http://127.0.0.1:22000/ || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
