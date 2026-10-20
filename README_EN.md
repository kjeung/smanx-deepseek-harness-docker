# deepseek-harness

English | [中文](README.md)

Deploy **DeepSeek Harness (DSH)** + **Node reverse proxy** with Docker:

1. Install and start DSH inside the container (official npm package `@deepseek-ai/dsh` from [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)), listening on `127.0.0.1:3079` (source port) by default;
2. Start a Node proxy: `0.0.0.0:3080` (proxy port) → `127.0.0.1:3079`, providing LAN access + WebSocket forwarding.

> Why proxy instead of exposing DSH directly:
> - DSH forbids `--host 0.0.0.0` (security restriction), so it can only listen on the loopback address;
> - Pages loaded over a LAN IP are in a browser **non-secure context**, where the `crypto.randomUUID` used by the DSH frontend is unavailable.
>   The proxy injects a polyfill to work around it (otherwise the realtime channel/WS stays pending forever);
> - The proxy also provides **HTTP Basic Auth** to protect LAN access.

## Directory Structure

```
deepseek-harness/
├── Dockerfile            # node:24-slim + install DSH + proxy (supports DEV_TOOLS build arg; admin variant pre-installs the latest DSH)
├── entrypoint.sh         # start DSH first, wait until ready, then start the proxy (detects the admin variant marker and runs the manager service instead)
├── proxy/
│   ├── index.js          # proxy (forwarding + polyfill injection + Origin alignment + Basic Auth)
│   └── package.json
├── manager/              # admin variant only: install/switch DSH versions from the page, configure npm registry, manage the DSH process
│   ├── index.js
│   ├── admin.html
│   └── package.json
└── README.md / README_EN.md
```

## Usage

```bash
# Enter the project directory
cd deepseek-harness

# Build the image (default slim runtime image, no dev tools)
docker build -t smanx/deepseek-harness .

# Run (defaults: proxy port 3080, data persisted to named volume dsh-data)
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness

# View logs
docker logs -f dsh-harness

# Stop / remove (volume data is kept)
docker stop dsh-harness
docker rm dsh-harness
```

Building installs DSH via npm (~250MB of dependencies), so the first build is slower than usual.
On Linux, node-pty has no prebuilt binaries and is compiled from source (the Dockerfile uses a
multi-stage build with python3/make/g++ installed; the runtime image does not keep the build tools).

The container runs as a non-root user, **`node` (UID/GID `1000:1000`)**: PID 1 and all application
processes are `node`, the data directory is `/home/node/.dsh`, and `/app` and `/usr/local` are
`root:root` and read-only. So `docker exec` runs as `node` by default
(`docker exec dsh-harness id` → `uid=1000(node)`); use `docker exec -u 0 dsh-harness id` when you
really need root (emergency troubleshooting only).

## Differences Between the Tags

The default runtime image is slim and does not keep build tools, suitable for production. If you
need to develop/debug inside the container, build with `--build-arg DEV_TOOLS=<tag-prefix>`.
Which tools each prefix installs is defined in the `.build-variants` file at the project root
(each line `<tag-prefix>|<apt packages>|<npm global packages>`; column 2 goes to apt-get install,
column 3 to npm install -g, and can be empty). Edit that file to add/remove tools dynamically
without touching the Dockerfile. Each tag also ships a matching **version tag** (the version
matches the `@deepseek-ai/dsh` version actually installed at build time, currently `<version>`):

| Tag (latest) | Version tag | Purpose | Included tools |
|---|---|---|---|
| `smanx/deepseek-harness:latest` | `smanx/deepseek-harness:<version>` | Original slim image, production-ready | No dev tools; pnpm 12.14.0 |
| `smanx/deepseek-harness:devtools-min-latest` | `smanx/deepseek-harness:devtools-min-<version>` | Minimal tools for common debugging | git, curl, wget, nano, jq, procps, ca-certificates, unzip; pnpm 12.14.0; uv |
| `smanx/deepseek-harness:devtools-latest` | `smanx/deepseek-harness:devtools-<version>` | Full tools for developing/compiling inside the container | everything in Minimal + vim, openssh-client, zip, htop, tmux, tree, openssl, python3, build-essential (make/g++), bash-completion; pnpm 12.14.0; uv |
| `smanx/deepseek-harness:test-latest` | `smanx/deepseek-harness:test-<version>` | Test tag: full tools + auto-installs DSH plugins | same as Full Tools (pnpm 12.14.0, uv); additionally runs `dsh plugin --profile web add github:smanx/dsh-fixed-providers#master` after DSH install |
| `smanx/deepseek-harness:admin-latest` | `smanx/deepseek-harness:admin-<version>` | Admin variant: **latest DSH pre-installed**, works out of the box; admin page to pick/install/switch versions | same as Full Tools (pnpm 12.14.0, uv) + manager service; keeps python3/build-essential to compile node-pty at runtime |

```bash
# Minimal tools (DEV_TOOLS matches the first column of .build-variants)
docker build -t smanx/deepseek-harness:devtools-min-<version> --build-arg DEV_TOOLS=devtools-min .

# Full tools
docker build -t smanx/deepseek-harness:devtools-<version> --build-arg DEV_TOOLS=devtools .
```

> GitHub Actions (`docker-build/.github/workflows/projects.yml`) reads the `.build-variants`
> manifest in each project directory and automatically builds and pushes all tags (Docker Hub
> and GHCR, one set each).

> The full-tools version includes `python3` + `build-essential`, so native modules (e.g. node-pty)
> can be compiled directly inside the container — it effectively also brings the build tools of the
> `dsh-builder` stage into the runtime image. The version follows the actual `@deepseek-ai/dsh`
> release; e.g. after upgrading to `0.2.0`, change the tags to `devtools-0.2.0` / `devtools-min-0.2.0`.

> **pnpm 12.14.0 is built into every variant** (including the slim `latest`): the Dockerfile
> installs it once, and at runtime it is read-only+executable for `node`. DSH's `dsh plugin` command
> relies on pnpm to manage plugins, and the community plugin market
> [dsh-market](https://github.com/dsh-market/dsh-market) (`dsh plugin --profile web add dshmarket`)
> works out of the box — no pnpm installation needed.
>
> `github:` plugins (e.g. `dsh plugin --profile web add github:owner/repo`) need `git` to install.
> Only the **devtools / devtools-min / test / admin** variants include git; on the slim `latest`,
> install plugins by npm package name instead.
>
> The tooled variants (devtools-min / devtools / test / admin) also bundle **uv** (Python package manager, static binary, no system Python
> required). Many community MCP servers launch via `uvx` / `uv run` (commonly seen in DSH MCP
> client configs as `"command": "uvx"`); without uv those MCPs cannot run. uv downloads the Python
> interpreter on demand on first use.

### Admin Variant (latest DSH pre-installed)

The `admin` variant **pre-installs the latest DSH (@next)**. After the container starts, the manager
service detects and starts DSH automatically, so `/` serves the DSH UI directly; visiting `/__admin/`
opens the admin page, where you can:

- Browse the available versions of the npm package `@deepseek-ai/dsh` (dist-tags like `latest`/`next`
  plus the full version list), select and **install / switch** DSH versions, with live install progress;
- Manually configure the **npm registry (NPM_CONFIG_REGISTRY)**: the input field **auto-fills the
  default value** (env `NPM_CONFIG_REGISTRY` or the official registry `https://registry.npmjs.org/`)
  and the **last-saved value**, and shows the effective value; you can restore the default or clear
  it with one click. Priority: **page config > env `NPM_CONFIG_REGISTRY` > default**;
- **Restart** DSH with one click. After install, DSH starts automatically and a floating "⚙ Admin"
  button stays in the corner of the DSH page so you can always get back to the admin page.

Run command (two named volumes: `dsh-data` for DSH config/sessions, `dsh-install` for the installed
DSH files and config state, so upgrades/registry survive container recreation):

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -v dsh-install:/opt/dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:admin-latest
```

> The admin variant keeps `python3` + `build-essential`: node-pty has no Linux prebuilt binaries,
> and installing other DSH versions from the page requires compiling the native module from source
> inside the container, so this image is a bit larger than the slim one. Since the admin variant
> pre-installs the latest DSH, its version tag is the DSH version (e.g. `admin-0.1.1`).
> The admin variant must write `/opt/dsh`, `/home/node/.dsh` and `/tmp`, so it does **not** support
> `--read-only`.

## Runtime User and Permissions (non-root)

Every variant runs as `node` (UID/GID `1000:1000`); the image sets `USER node` statically:

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

## Optional Hardening

```bash
# Least privilege + no privilege escalation (all variants)
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

## Port Configuration

The source port (DSH) and proxy port (external) can both be configured via environment variables:

| Environment variable | Meaning | Default |
|---|---|---|
| `DSH_PORT` | Source port: where DSH listens (container `127.0.0.1`) | `3079` |
| `PROXY_PORT` | Proxy port: where the proxy listens (LAN entry point) | `3080` |

> The two must differ (one port can only be bound by one process).

The admin variant also supports these environment variables:

| Environment variable | Meaning | Default |
|---|---|---|
| `NPM_CONFIG_REGISTRY` | Default npm registry on the admin page (used when not configured on the page; lower priority than the page config) | `https://registry.npmjs.org/` |
| `DSH_INSTALL_DIR` | DSH install directory in the admin variant (installed DSH and state files live here; mount a named volume) | `/opt/dsh` |

For example, change to "DSH internal 3082, proxy external 3080":

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -e DSH_PORT=3082 \
  --restart unless-stopped \
  smanx/deepseek-harness
```

## Access

- Local: `http://127.0.0.1:3080/`
- LAN: `http://<server-LAN-IP>:3080/` (e.g. `http://192.168.1.100:3080/`)
- The WebSocket realtime channels are forwarded automatically by the proxy (`/api/events.mux`, `/api/events.host`)

## Basic Auth (optional)

Set the environment variables before starting; auth is enabled only when **both** are set:

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -e PROXY_USERNAME=yourname \
  -e PROXY_PASSWORD=yourpass \
  --restart unless-stopped \
  smanx/deepseek-harness
```

- Auth applies to both HTTP and WebSocket; unauthenticated requests get `401` + `WWW-Authenticate`
  and the browser shows a credential prompt;
- If neither (or only one) is set, access is completely open (no auth required);
- The public static resources `/manifest.webmanifest`, `/favicon.svg`, `/favicon.ico` are exempt
  from auth (they only contain non-sensitive data like the app name/icon). Browsers fetching
  `<link rel="manifest">` do not send Basic Auth credentials; if auth were enforced on these paths,
  the console would keep reporting `/manifest.webmanifest` 401.

## Data Persistence

DSH session/config data is stored in the named volume `dsh-data` (container path `/home/node/.dsh`).
The volume survives `docker stop/start` and container removal; to wipe it completely, stop the
container first, then `docker volume rm dsh-data`.

To use a bind mount instead, hand the host directory to UID/GID `1000` first:

```bash
sudo mkdir -p /srv/dsh-data
sudo chown -R 1000:1000 /srv/dsh-data
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v /srv/dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness
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
  smanx/deepseek-harness
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

## Notes

- DSH officially forbids `--host 0.0.0.0`, so DSH stays on the loopback interface inside the
  container; the proxy handles external access;
- If DSH fails to start under `node:24-slim` due to missing system libraries, change the base image
  of both Dockerfile stages to `node:24` and rebuild;
- The proxy logic is identical to the standalone [dsh-proxy](https://github.com/smanx/dsh-proxy)
  (polyfill injection, Origin alignment, Basic Auth, WS forwarding).
- The DSH frontend uses `connection.isLoopback` to decide whether settings-type features are
  available (plugin config cards, settings file buttons, etc.), and only counts `localhost`/
  `127.x.x.x` etc. loopback hostnames as loopback. When accessed via a hostname/LAN IP these
  features are hidden (e.g. the "Plugin Config" page drops from 3 cards to an empty list). The proxy
  rewrites the `isLoopbackHostname(pageLocation.hostname)` check to always-true when forwarding JS,
  so LAN access can use settings features as well.
