# deepseek-harness (Docker Image)

Image (default): **`smanx/deepseek-harness:latest`** (Docker Hub)
Image (backup): **`ghcr.io/smanx/deepseek-harness:latest`** (GitHub Container Registry, GHCR; all tags are mirrored there)
Docker Hub project page: https://hub.docker.com/r/smanx/deepseek-harness
Github project page：https://github.com/smanx/deepseek-harness-docker

An out-of-the-box **DeepSeek Harness (DSH)** Docker image with a built-in Node reverse proxy. It solves the issue that DSH officially forbids `--host 0.0.0.0` (loopback-only listening) and makes DSH safely accessible over your LAN.

## Online Demo

- Demo URL: https://dsh.smanx.xx.kg
- Username / Password: `admin` / `admin`

> ⚠️ **Note:** This is a **public address**. If you fill in your own API key (e.g. DeepSeek), please be **very careful** — your key may be exposed.

## About the Project

- **DSH**: Installs the official npm package `@deepseek-ai/dsh` ([deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)) inside the container, listening on `127.0.0.1:3079` (source port) by default;
- **Node proxy**: `0.0.0.0:3080` (proxy port) → `127.0.0.1:3079`, providing HTTP + WebSocket forwarding to the outside;
- **Why a proxy is needed**:
  - DSH officially forbids `--host 0.0.0.0` (security restriction) and can only listen on the loopback address;
  - Pages loaded over a LAN IP are in a browser **non-secure context**, where the `crypto.randomUUID` used by the DSH frontend is unavailable. The proxy automatically injects a `getRandomValues`-based polyfill into served HTML; without it the realtime channel (WS) stays pending forever;
  - The proxy also provides optional **HTTP Basic Auth** to protect LAN access.

## Quick Start (pull & run)

```bash
# 1. Pull the image (default: Docker Hub)
docker pull smanx/deepseek-harness:latest

# 2. Run (defaults: proxy port 3080, data persisted to named volume dsh-data)
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# 3. Access
#    Local machine: http://127.0.0.1:3080/
#    LAN:           http://<server-LAN-IP>:3080/
```

The WebSocket realtime channels (`/api/events.mux`, `/api/events.host`) are forwarded automatically by the proxy — no extra configuration needed.

### Differences between the tags

| Tag | Purpose | Included tools |
|---|---|---|
| `latest` | Slim runtime image | No dev tools; pnpm 12.14.0 |
| `devtools-min-latest` | Minimal tools for common debugging | git, curl, wget, nano, jq, procps, ca-certificates, unzip; pnpm 12.14.0; uv |
| `devtools-latest` | Full tools for developing/compiling inside the container | everything in Minimal + vim, openssh-client, zip, htop, tmux, tree, openssl, python3, build-essential (make/g++), bash-completion; pnpm 12.14.0; uv |
| `admin-latest` | Admin variant: **latest DSH pre-installed**, works out of the box; admin page to pick/install/switch versions | same as Full Tools (pnpm 12.14.0, uv) + manager service; keeps python3/build-essential to compile node-pty at runtime |

> Each tag also has a matching **versioned tag**: `latest` ↔ `<version>`, `devtools-latest` ↔ `devtools-<version>`, `devtools-min-latest` ↔ `devtools-min-<version>`, `admin-latest` ↔ `admin-<version>` (admin pre-installs the latest DSH, so its version tag is the DSH version).

**A simple example:**

```bash
# Scenario 1: just run DSH in the browser with no debugging → use the slim `latest`
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# Scenario 2: you need to get inside the container to troubleshoot
# (view logs, process JSON with jq, fetch things with wget) → use devtools-min-latest
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:devtools-min-latest

# Scenario 3: develop/compile inside the container or do heavier ops
# (vim, python3, make, etc.) → use devtools-latest
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:devtools-latest
```

The run command is identical across all three tags — only the image name (tag) changes. The tooled variants are a bit larger than the slim image, so pick what fits.

**pnpm 12.14.0 is built into every tag**, including the slim `latest` (installed once in the
Dockerfile, read-only+executable for `node` at runtime). DSH's `dsh plugin` command relies on pnpm to
manage plugins, and the community plugin market [dsh-market](https://github.com/dsh-market/dsh-market)
(`dsh plugin --profile web add dshmarket`) works out of the box — no pnpm installation needed.

`github:` plugins need `git` to install, and only the devtools / devtools-min / test / admin variants
include git; on the slim `latest`, install plugins by npm package name instead.

The tooled variants (devtools-min / devtools / test / admin) also ship **uv** (Python package manager, static binary, no system Python required).
Many community MCP servers launch via `uvx` / `uv run` (commonly seen in DSH MCP client configs as
`"command": "uvx"`) — without uv those MCPs cannot run.

All variants run as the non-root user **`node` (UID/GID `1000:1000`)**: `docker exec` defaults to
node (`docker exec dsh-harness id` → `uid=1000(node)`), `docker exec -u 0` is for emergency
troubleshooting only, the data directory is `/home/node/.dsh`, and `/app` / `/usr/local` are read-only.

#### Admin variant (latest DSH pre-installed)

The `admin` variant **pre-installs the latest DSH (@next)**. After the container starts, the manager service detects and starts DSH automatically, so `/` serves the DSH UI directly; visiting `/__admin/` opens the admin page, where you can:

- Browse available versions of `@deepseek-ai/dsh` (dist-tags like `latest`/`next` plus the full list) and **install / switch** versions, with live install logs;
- Configure the **npm registry (NPM_CONFIG_REGISTRY)** manually: the input field **auto-fills the default** (env `NPM_CONFIG_REGISTRY` or the official registry) and the **last-saved value**, and shows the effective value; you can restore the default or clear it with one click. Priority: **page config > env `NPM_CONFIG_REGISTRY` > default**;
- **Restart** DSH with one click. After install it starts automatically, and a floating "⚙ Admin" button stays in the corner of the DSH page so you can always get back to the admin page.

```bash
# Admin variant: use two named volumes (dsh-data for DSH config/sessions, dsh-install for the
# installed DSH files and config state, so upgrades/registry survive container recreation)
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -v dsh-install:/opt/dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:admin-latest
```

> The admin variant keeps `python3` + `build-essential` (node-pty has no Linux prebuilds, so installing other DSH versions from the page needs to compile the native module from source in-container), making the image a bit larger than the slim one.
> Admin must write `/opt/dsh`, `/home/node/.dsh` and `/tmp`, so it does **not** support `--read-only`.

### Runtime user and permissions (non-root)

Every tag runs as `node` (UID/GID `1000:1000`); the image sets `USER node` statically:

| Path | Owner / mode | Purpose |
|---|---|---|
| `/app` | `root:root 0755` | proxy and manager code, read-only |
| `/usr/local` | `root:root 0755` | Node and global DSH packages, read-only+executable |
| `/home/node/.dsh` | `1000:1000` | DSH data directory (mount a named volume) |
| `/opt/dsh` | `1000:1000` | admin DSH install directory (mount a named volume) |
| `/tmp` | writable | logs `/tmp/.dsh-web.log`, launch token `/tmp/.dsh-launch-token` (`0600`) |

- `docker exec` defaults to `node`; `docker exec -u 0` is an emergency escape hatch only;
- **bind mounts** follow the host directory's ownership: run `sudo chown -R 1000:1000 <host-dir>`
  before mounting, otherwise `node` cannot write the data directory;
- named volumes inherit their owner on first mount and are independent of the host UID — prefer them.

### Optional hardening

```bash
# Least privilege + no privilege escalation (all tags)
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# Read-only rootfs (latest / devtools-min / devtools / test; not supported by admin)
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --read-only \
  --tmpfs /tmp:rw,exec,size=64m \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

- `--read-only` only makes the rootfs read-only; named volumes and tmpfs stay writable — logs, token
  and temporary files all live in `/tmp`, hence `--tmpfs /tmp` with an explicit `exec`: Docker mounts
  tmpfs `noexec` by default, and DSH copies its native bindings into `/tmp` before loading them, so
  omitting `exec` makes startup fail;
- Do not add `noexec` to `/tmp`: DSH writes shell integration scripts and native-binding caches there,
  and `noexec` may break tool execution or startup;
- Under `--read-only`, `$HOME` is read-only except the `/home/node/.dsh` volume: `dsh plugin` installs
  still work, but first-run `uv`/`uvx` Python downloads and npm global caches that write `$HOME` do not;
- admin writes `/opt/dsh`, `/home/node/.dsh`, `/tmp` and the npm cache, so it does not support `--read-only`;
- the static `USER node` needs no root initialization, so `--cap-drop=ALL` does not break startup
  (there are no chown/setuid steps).

## Quick Start (pull & run)

### Backup Image (GHCR)

If pulling from Docker Hub is restricted (e.g. network issues), you can use the backup image (GitHub Container Registry; tags are identical to Docker Hub):

```bash
# Pull the image from GHCR
docker pull ghcr.io/smanx/deepseek-harness:latest

# Same run command as the default image — just swap the image name
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  ghcr.io/smanx/deepseek-harness:latest
```

> The two images are identical in configuration and usage — only the registry differs, so they are interchangeable.

## Configuration (Environment Variables)

| Variable | Meaning | Default |
|---|---|---|
| `DSH_PORT` | Source port: where DSH listens inside the container (`127.0.0.1`) | `3079` |
| `PROXY_PORT` | Proxy port: where the proxy listens (LAN entry point) | `3080` |
| `PROXY_USERNAME` | Basic Auth username (optional) | unset |
| `PROXY_PASSWORD` | Basic Auth password (optional) | unset |
| `NPM_CONFIG_REGISTRY` | Default npm registry on the admin page (lower priority than the page config) | `https://registry.npmjs.org/` |
| `DSH_INSTALL_DIR` | DSH install directory in the admin variant (installed DSH and config state live here; mount a named volume) | `/opt/dsh` |

> `DSH_PORT` and `PROXY_PORT` must differ (a port can only be bound by one process).
> If you change `PROXY_PORT`, remember to update the port mapping accordingly: `-p <host-port>:<new-proxy-port>`.

### Enabling Basic Auth

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -e PROXY_USERNAME=yourname \
  -e PROXY_PASSWORD=yourpass \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

- Auth is enabled **only when both** username and password are set; if either (or both) is missing, access is completely open;
- Auth applies to both HTTP and WebSocket. Unauthenticated requests get `401` + `WWW-Authenticate`, and the browser shows a credential prompt.

### Changing the proxy port

```bash
# e.g. expose the proxy on port 3088
docker run -d \
  --name dsh-harness \
  -p 3088:3088 \
  -v dsh-data:/home/node/.dsh \
  -e PROXY_PORT=3088 \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

## Data Persistence

DSH session/configuration data lives in `/home/node/.dsh` inside the container; the commands above persist it via the named volume `dsh-data`:

- Data survives `docker stop/start` and container removal;
- To wipe it completely: `docker volume rm dsh-data` (stop the container first).

To use a bind mount instead, hand the host directory to UID/GID `1000` first:

```bash
sudo mkdir -p /srv/dsh-data
sudo chown -R 1000:1000 /srv/dsh-data
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v /srv/dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

## Workspace Persistence

DSH workspaces (where the agent actually reads/writes project files) are not inside the
`/home/node/.dsh` data volume. When no system Documents directory exists, the first page load
does not create a default workspace; `/home/node/workspace` is the suggested path, and that
directory lives in the container's writable layer — files are lost when the container is
recreated.

Mount the host project directory at that default path; accept the suggested workspace on first
entry and data lands on the host:

```bash
sudo mkdir -p /srv/dsh-workspace
sudo chown -R 1000:1000 /srv/dsh-workspace
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -v /srv/dsh-workspace:/home/node/workspace \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

No default workspace on first entry is expected: create/select a workspace and accept
`/home/node/workspace` (or pick `workspace` under HOME); sessions then read/write there and
survive container restarts/recreation.

Notes:

- Do not use `working_dir` to choose the workspace; it only sets the process cwd and does not
  affect the default workspace path or the picker.
- To keep using `/workspace` as the workspace path, mount the host directory at `/workspace` and
  add `/workspace` manually in the UI. Both approaches need one manual selection on first use.
- If a workspace was previously created inside the container at `/home/node/workspace` (not a
  mount), copy it out first (`docker cp dsh-harness:/home/node/workspace ./backup`), otherwise the
  mount will hide it.

## Stop / Restart / Remove

```bash
docker stop dsh-harness     # stop
docker start dsh-harness    # start again
docker logs -f dsh-harness  # view logs
docker rm -f dsh-harness    # remove the container (volume data is kept)
```

## Contact & Feedback

- Discussion & bug feedback: https://github.com/deepseek-ai/deepseek-harness/discussions/1762
