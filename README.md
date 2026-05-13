# Grand Theft Auto Connected Server

> ⚠️ **Beta** — unofficial Docker packaging of the [Grand Theft Auto Connected](https://gtaconnected.com/) dedicated server. Not affiliated with the GTAC project.

Self-hosted **Grand Theft Auto Connected** dedicated server in a container. The image is base-only — it grabs the latest Linux server binary from `gtaconnected.com/downloads/` on every start, so a `docker restart` is your update mechanism. Pin a specific build by setting `GTAC_VERSION`.

> ⚠️ **First-boot gotcha:** the stock upstream `server.xml` defaults to `<game>gta:iii</game>` (GTA III). If you're hosting **GTA IV**, edit `/config/server.xml` after the first boot and change `gta:iii` → `gta:iv` (and set `iv_episode` / `iv_gamemode` to suit), or any GTA IV client will be kicked with **"UNSUPPORTED ENGINE"**. Restart the container after editing.

## Features

- **Auto-updating** — entrypoint resolves the newest `GTAC-Server-Linux-*.tar.gz` (or whatever you pin) and extracts it before launch.
- **Native Linux build** — no Wine. Small image (~150 MB), low overhead.
- **AMD64 + ARM64** — auto-detected from the host; pin via `GTAC_ARCH` if cross-running.
- **Config separation** — `/config` holds `server.xml`, `resources/`, and `htdocs/`. Edit them on the host without touching the image.
- **Logs out** — `/data/logs` for log persistence across restarts.
- **Non-root** — runs as uid/gid 1000:1000 inside the container.
- **Healthcheck** — hits the built-in HTTP server on port 22000.

## Quick start

```bash
docker run -d --name gtac --restart unless-stopped \
  -p 22000:22000/tcp -p 22000:22000/udp \
  -v /mnt/user/appdata/gtac/config:/config \
  -v /mnt/user/appdata/gtac/data:/data \
  mightyrufo/gtac-server:latest
```

On first boot, `/config/server.xml` and `/config/resources/freeroam/` are seeded from the upstream archive. Edit them, then `docker restart gtac` to apply.

## Environment variables

| Var | Default | Description |
|---|---|---|
| `GTAC_VERSION` | *(empty)* | Pin to a specific build (e.g. `1.7.3`). Empty = auto-detect latest from the downloads page on every start. |
| `GTAC_DOWNLOADS_URL` | `https://gtaconnected.com/downloads/` | Override only if mirroring upstream. |
| `GTAC_ARCH` | *(auto)* | Force `AMD64` or `ARM64`. Auto-detected from `uname -m` when empty. |
| `GTAC_SKIP_UPDATE` | `0` | Set to `1` to bypass the update check entirely. Useful air-gapped, once `/opt/gtac` is populated. |

## Volumes

| Path | Purpose |
|---|---|
| `/config` | `server.xml`, `resources/`, `htdocs/`. Edit on the host; the entrypoint symlinks these into `/opt/gtac` at start. |
| `/data` | Logs (`/data/logs`). |

## Ports

| Port | Proto | Purpose |
|---|---|---|
| 22000 | TCP + UDP | Game traffic. Also the built-in HTTP server (`<httpserver>true</httpserver>` in `server.xml`). |

If you change `<port>` in `server.xml`, remember to remap the container ports to match.

## Updating

```bash
docker restart gtac
```

The entrypoint will pick up any newer Linux build published on `gtaconnected.com/downloads/`, replace `/opt/gtac/Server`, and start it. Your `/config` is untouched.

To pin to a known-good version:

```bash
docker run ... -e GTAC_VERSION=1.7.3 mightyrufo/gtac-server:latest
```

## Adding resources

Drop your resource folder into `/config/resources/` on the host:

```
/mnt/user/appdata/gtac/config/
├── server.xml
├── resources/
│   ├── freeroam/
│   └── modmenu/           ← your custom resource
└── htdocs/
```

Then add it to `<resources>` in `server.xml`:

```xml
<resources>
    <resource src="freeroam" />
    <resource src="modmenu" />
</resources>
```

Restart the container.

## Unraid

1. Either paste this URL into Unraid → Docker → Add Container → Template:
   `https://raw.githubusercontent.com/MightyRufo/gtac-server/main/my-Grand-Theft-Auto-Connected-Server.xml`
   …or drop [`my-Grand-Theft-Auto-Connected-Server.xml`](./my-Grand-Theft-Auto-Connected-Server.xml) into `/boot/config/plugins/dockerMan/templates-user/` as-is.
2. Docker tab → Add Container → User templates → **gtac-server**.
3. Configure the volume paths and start.

## Build from source

```bash
git clone https://github.com/MightyRufo/gtac-server
cd gtac-server
docker build -t gtac-server:dev .
docker run --rm -p 22000:22000/tcp -p 22000:22000/udp \
  -v $(pwd)/config:/config -v $(pwd)/data:/data \
  gtac-server:dev
```

## License

MIT — see [`LICENSE`](./LICENSE). GTA Connected itself is © its respective authors and distributed under its own terms.
