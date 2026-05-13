#!/bin/sh
# GTAC Server entrypoint.
#  - Resolves the target version (env pin OR latest from downloads page).
#  - Downloads + extracts to /opt/gtac if local copy is missing or stale.
#  - Seeds /config with default server.xml and resources/ on first boot.
#  - Symlinks server.xml, resources, htdocs to /config so the user owns config.
#  - Symlinks logs to /data/logs so they survive container recreates.
#  - Re-execs as the unprivileged `gtac` user, then runs Server.
set -eu

GTAC_HOME="/opt/gtac"
CONFIG_DIR="/config"
DATA_DIR="/data"
DOWNLOADS_URL="${GTAC_DOWNLOADS_URL:-https://gtaconnected.com/downloads/}"
SKIP_UPDATE="${GTAC_SKIP_UPDATE:-0}"
VERSION_FILE="$GTAC_HOME/.version"

log() { echo "gtac: $*"; }

detect_arch() {
  if [ -n "${GTAC_ARCH:-}" ]; then
    echo "$GTAC_ARCH"
    return
  fi
  case "$(uname -m)" in
    x86_64|amd64) echo "AMD64" ;;
    aarch64|arm64) echo "ARM64" ;;
    *) echo "AMD64" ;;  # fall back; will fail loud below if wrong
  esac
}

resolve_version() {
  # If GTAC_VERSION is pinned, trust it.
  if [ -n "${GTAC_VERSION:-}" ]; then
    echo "$GTAC_VERSION"
    return
  fi
  # Otherwise scrape the downloads page for the newest Linux build.
  html="$(curl -fsSL -A "gtac-docker/1.0" "$DOWNLOADS_URL" 2>/dev/null || true)"
  if [ -z "$html" ]; then
    log "WARN: could not reach $DOWNLOADS_URL — falling back to local copy"
    return
  fi
  # Extract version numbers from "GTAC-Server-Linux-*.tar.gz" filenames.
  echo "$html" \
    | grep -oE 'GTAC-Server-Linux-(ARM64-)?[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
    | sed -E 's/GTAC-Server-Linux-(ARM64-)?//; s/\.tar\.gz//' \
    | sort -V -u | tail -1
}

download_and_extract() {
  version="$1"
  arch="$2"
  if [ "$arch" = "ARM64" ]; then
    fname="GTAC-Server-Linux-ARM64-${version}.tar.gz"
  else
    fname="GTAC-Server-Linux-${version}.tar.gz"
  fi
  url="$(echo "$DOWNLOADS_URL" | sed 's:/*$::')/server/${fname}"
  tmp="/tmp/gtac-${version}.tar.gz"

  # Clean leftovers from any previous interrupted run before we start.
  rm -f /tmp/gtac-*.tar.gz 2>/dev/null || true
  rm -rf /tmp/gtac-stage-* 2>/dev/null || true

  log "fetching ${fname}"
  if ! curl -fsSL -A "gtac-docker/1.0" "$url" -o "$tmp"; then
    log "ERROR: download failed: $url"
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi

  staging="/tmp/gtac-stage-$$"
  mkdir -p "$staging"
  if ! tar -xzf "$tmp" -C "$staging"; then
    log "ERROR: extract failed for $tmp"
    rm -f "$tmp"
    rm -rf "$staging"
    return 1
  fi
  rm -f "$tmp"

  # GTAC archives ship a flat layout (Server, libmozjs-60.so, server.xml, resources/).
  # Wipe binaries from /opt/gtac but keep nothing config-related (those live in /config).
  rm -f  "$GTAC_HOME/Server" "$GTAC_HOME"/*.so 2>/dev/null || true
  rm -rf "$GTAC_HOME/_defaults" 2>/dev/null || true

  mkdir -p "$GTAC_HOME/_defaults"
  # Copy binaries + libs into /opt/gtac
  find "$staging" -maxdepth 1 -type f \( -name 'Server' -o -name '*.so*' \) -exec cp -a {} "$GTAC_HOME/" \;
  chmod +x "$GTAC_HOME/Server" 2>/dev/null || true

  # Stash the default config + resources for first-boot seeding.
  if [ -f "$staging/server.xml" ]; then
    cp -a "$staging/server.xml" "$GTAC_HOME/_defaults/server.xml"
  fi
  if [ -d "$staging/resources" ]; then
    cp -a "$staging/resources" "$GTAC_HOME/_defaults/resources"
  fi
  if [ -d "$staging/htdocs" ]; then
    cp -a "$staging/htdocs" "$GTAC_HOME/_defaults/htdocs"
  fi

  echo "$version" > "$VERSION_FILE"
  rm -rf "$staging"
  log "installed GTAC server $version ($arch)"
}

seed_config() {
  # First-boot: copy default server.xml + resources/ into /config so the user
  # can edit them. Never overwrite anything that already exists in /config.
  if [ ! -f "$CONFIG_DIR/server.xml" ] && [ -f "$GTAC_HOME/_defaults/server.xml" ]; then
    cp -a "$GTAC_HOME/_defaults/server.xml" "$CONFIG_DIR/server.xml"
    log "seeded $CONFIG_DIR/server.xml"
  fi
  if [ ! -d "$CONFIG_DIR/resources" ] && [ -d "$GTAC_HOME/_defaults/resources" ]; then
    cp -a "$GTAC_HOME/_defaults/resources" "$CONFIG_DIR/resources"
    log "seeded $CONFIG_DIR/resources/"
  fi
  if [ ! -d "$CONFIG_DIR/htdocs" ]; then
    if [ -d "$GTAC_HOME/_defaults/htdocs" ]; then
      cp -a "$GTAC_HOME/_defaults/htdocs" "$CONFIG_DIR/htdocs"
    else
      mkdir -p "$CONFIG_DIR/htdocs"
    fi
  fi
}

link_runtime() {
  # Replace anything in /opt/gtac that should come from /config or /data.
  for name in server.xml resources htdocs; do
    rm -rf "$GTAC_HOME/$name"
    ln -s  "$CONFIG_DIR/$name" "$GTAC_HOME/$name"
  done
  rm -rf "$GTAC_HOME/logs"
  mkdir -p "$DATA_DIR/logs"
  ln -s "$DATA_DIR/logs" "$GTAC_HOME/logs"
}

# ---- root pass: fix perms, then re-exec as gtac ----------------------------
if [ "$(id -u)" = "0" ]; then
  chown -R gtac:gtac "$GTAC_HOME" "$CONFIG_DIR" "$DATA_DIR" 2>/dev/null || true
  exec su -s /bin/sh gtac -c "$(printf '%s ' "$0" "$@")"
fi

mkdir -p "$GTAC_HOME" "$CONFIG_DIR" "$DATA_DIR/logs"

current_version=""
[ -f "$VERSION_FILE" ] && current_version="$(cat "$VERSION_FILE")"
arch="$(detect_arch)"

if [ "$SKIP_UPDATE" = "1" ] && [ -x "$GTAC_HOME/Server" ]; then
  log "GTAC_SKIP_UPDATE=1, using local $GTAC_HOME/Server (version ${current_version:-unknown})"
else
  target_version="$(resolve_version || true)"
  if [ -z "$target_version" ] && [ -x "$GTAC_HOME/Server" ]; then
    log "no target version resolved, keeping local copy (${current_version:-unknown})"
  elif [ -z "$target_version" ]; then
    log "FATAL: no target version resolved AND no local Server binary present"
    exit 1
  elif [ "$target_version" = "$current_version" ] && [ -x "$GTAC_HOME/Server" ]; then
    log "GTAC server $current_version up to date"
  else
    log "updating: ${current_version:-none} -> $target_version"
    download_and_extract "$target_version" "$arch"
  fi
fi

seed_config
link_runtime

cd "$GTAC_HOME"
log "starting Server (PWD=$GTAC_HOME)"
exec "$GTAC_HOME/Server" "$@"
