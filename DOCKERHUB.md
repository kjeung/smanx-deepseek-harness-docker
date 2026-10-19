# deepseek-harness（Docker 镜像）

镜像地址（默认）：**`smanx/deepseek-harness:latest`**（Docker Hub）
镜像地址（备用）：**`ghcr.io/smanx/deepseek-harness:latest`**（GitHub Container Registry，GHCR，所有 tag 同步推送）
Docker Hub 项目主页：https://hub.docker.com/r/smanx/deepseek-harness
Github 项目主页：https://github.com/smanx/deepseek-harness-docker


一个开箱即用的 **DeepSeek Harness（DSH）** Docker 镜像，内置了 Node 反向代理，解决 DSH 官方不允许 `--host 0.0.0.0`、只能监听回环地址的问题，让 DSH 可以安全地通过局域网访问。

## 在线体验地址（Demo）

- 体验地址：https://dsh.smanx.xx.kg
- 登录账号 / 密码：`admin` / `admin`

> ⚠️ **注意：** 该地址为**公开地址**。如需填入你自己的 API Key（如 DeepSeek 等），请**谨慎填写**，以免 Key 泄露。

## 项目介绍

- **DSH**：容器内安装官方 npm 包 `@deepseek-ai/dsh`（[deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)），默认监听容器内 `127.0.0.1:3079`（源端口）；
- **Node 代理**：`0.0.0.0:3080`（代理端口）→ `127.0.0.1:3079`，对外提供 HTTP + WebSocket 转发；
- **为什么需要代理**：
  - DSH 官方禁止 `--host 0.0.0.0`（安全限制），只能监听回环地址；
  - 局域网 IP 页面属于浏览器**非安全上下文**，DSH 前端依赖的 `crypto.randomUUID` 不可用，代理在转发 HTML 时自动注入基于 `getRandomValues` 的 polyfill，否则实时通道（WS）会一直 pending；
  - 代理同时提供可选的 **HTTP Basic Auth**，给局域网访问加认证。

## 快速开始（拉取运行）

```bash
# 1. 拉取镜像（默认从 Docker Hub 拉取）
docker pull smanx/deepseek-harness:latest

# 2. 启动（默认：代理对外端口 3080，数据持久化到命名卷 dsh-data）
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# 3. 访问
#    本机：  http://127.0.0.1:3080/
#    局域网：http://<服务器局域网IP>:3080/
```

WebSocket 实时通道（`/api/events.mux`、`/api/events.host`）由代理自动转发，无需额外配置。

### 不同 tag 的区别

| tag | 定位 | 包含工具 |
|---|---|---|
| `latest` | 精简运行镜像 | 无开发工具；pnpm 12.14.0 |
| `devtools-min-latest` | 精简工具版，常用调试工具 | git、curl、wget、nano、jq、procps、ca-certificates、unzip；pnpm 12.14.0；uv |
| `devtools-latest` | 完整工具版，可在容器内开发/编译 | 精简版全部 + vim、openssh-client、zip、htop、tmux、tree、openssl、python3、build-essential(make+g++)、bash-completion；pnpm 12.14.0；uv |
| `admin-latest` | 管理版：**预装最新 DSH**，开箱即用，页面自选版本安装/切换 | 同完整工具版（含 pnpm 12.14.0、uv）+ 管理服务；保留 python3/build-essential 供运行时编译 node-pty |

> 每个 tag 都有对应的**版本号 tag**：`latest` ↔ `<版本>`、`devtools-latest` ↔ `devtools-<版本>`、`devtools-min-latest` ↔ `devtools-min-<版本>`、`admin-latest` ↔ `admin-<版本>`（admin 预装最新 DSH，版本号 tag 即为 DSH 版本）。

**简单示例：**

```bash
# 场景一：只想在浏览器里跑 DSH，不做任何调试 → 用精简的 latest
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# 场景二：需要进容器排查问题（看日志、jq 处理 JSON、wget 抓包）→ 用 devtools-min-latest
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:devtools-min-latest

# 场景三：要在容器里开发/编译扩展或做较重的运维（vim、python3、make 等）→ 用 devtools-latest
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:devtools-latest
```

三个 tag 的启动命令完全一样，只是把镜像名替换成对应的 tag 即可；`latest` 之外的工具版镜像会比精简版略大，按需选择。

> **pnpm 12.14.0 已内置所有变体**（含精简版 `latest`），由 Dockerfile 统一安装，运行期以 `node`
> 用户只读+执行；DSH 的 `dsh plugin` 命令依赖它管理插件，社区插件市场
> [dsh-market](https://github.com/dsh-market/dsh-market)（`dsh plugin --profile web add dshmarket`）
> 也直接可用，无需再安装 pnpm。
>
> `github:` 形式的插件需要 `git`，只有 devtools / devtools-min / test / admin 变体带 git；
> 精简版 `latest` 请改用 npm 包名安装插件。
>
> 带开发工具的变体（devtools-min / devtools / test / admin）还内置 **uv**（Python 包管理器，静态二进制，不依赖系统 Python）。不少社区 MCP server 以
> `uvx` / `uv run` 方式启动（DSH 的 MCP 客户端配置中常见 `"command": "uvx"`），缺少 uv 时这类 MCP 无法运行。

> 所有变体都以非 root 用户 **`node`（UID/GID `1000:1000`）** 运行：`docker exec` 默认就是 node
> （`docker exec dsh-harness id` → `uid=1000(node)`），`docker exec -u 0` 仅作紧急排障；数据目录是
> `/home/node/.dsh`，`/app`、`/usr/local` 只读。

#### admin 变体（管理版，预装最新 DSH）

`admin` 变体**随镜像预装最新 DSH（@next）**。容器启动后管理服务自动识别并拉起 DSH，直接访问 `/` 即可进入 DSH 界面；访问 `/__admin/` 进入管理台：

- 查看 `@deepseek-ai/dsh` 可用版本（`latest`/`next` 等 dist-tag + 全部版本），选择并**安装 / 切换**版本，安装进度实时显示；
- 手动配置 **npm 源（NPM_CONFIG_REGISTRY）**：输入框**自动回显默认值**（环境变量 `NPM_CONFIG_REGISTRY` 或官方源）与**上次配置的值**，并显示当前生效值，可一键「使用默认值」或清空恢复默认；优先级：**页面配置 > 环境变量 `NPM_CONFIG_REGISTRY` > 默认值**；
- 一键**重启** DSH；安装完成后自动启动，页面右下角悬浮「⚙ 管理」按钮可随时回到管理台调整版本。

```bash
# admin 变体：需要两个命名卷（dsh-data 存 DSH 配置/会话、dsh-install 存 DSH 安装文件与配置状态，
# 这样容器重建后升级/源配置依然有效）
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -v dsh-install:/opt/dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:admin-latest
```

> admin 变体保留了 `python3` + `build-essential`（node-pty 在 Linux 上无预编译产物，管理台安装其他版本 DSH 时需容器内从源码编译原生模块），镜像比精简版略大。
> admin 需要写 `/opt/dsh`、`/home/node/.dsh` 与 `/tmp`，因此**不支持 `--read-only`**。

### 运行用户与权限（非 root）

所有 tag 都以 `node`（UID/GID `1000:1000`）运行，镜像内静态设置了 `USER node`：

| 路径 | 属主/权限 | 用途 |
|---|---|---|
| `/app` | `root:root 0755` | 代理与管理服务代码，只读 |
| `/usr/local` | `root:root 0755` | Node 与 DSH 全局包，只读+执行 |
| `/home/node/.dsh` | `1000:1000` | DSH 数据目录（建议挂命名卷） |
| `/opt/dsh` | `1000:1000` | admin 的 DSH 安装目录（建议挂命名卷） |
| `/tmp` | 可写 | 日志 `/tmp/.dsh-web.log`、launch token `/tmp/.dsh-launch-token`（`0600`） |

- `docker exec` 默认就是 `node` 用户；`docker exec -u 0` 只是紧急排障入口，不属于正常运行路径；
- **bind mount** 由宿主目录权限决定，挂载前先 `sudo chown -R 1000:1000 <宿主目录>`，否则容器内 `node` 无法写入数据目录；
- 命名卷首次挂载会继承属主，不受宿主 UID 影响，推荐优先使用。

### 可选加固

```bash
# 最小权限 + 禁止提权（所有 tag）
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --restart unless-stopped \
  smanx/deepseek-harness:latest

# 只读 rootfs（latest / devtools-min / devtools / test；admin 不支持）
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --read-only \
  --tmpfs /tmp:rw,exec,size=64m \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

- `--read-only` 只读 rootfs，命名卷与 tmpfs 仍可写；日志/token/临时文件都在 `/tmp`，因此要挂 `--tmpfs /tmp`，并显式带 `exec`：Docker 的 tmpfs 默认 `noexec`，而 DSH 会把原生绑定复制到 `/tmp` 再加载，缺 `exec` 时启动会失败；
- 不要在 `/tmp` 上加 `noexec`：DSH 会在 `/tmp` 写 shell 集成脚本与原生绑定缓存，`noexec` 会让工具执行或启动失败；
- 只读模式下 `$HOME` 除 `/home/node/.dsh` 卷外只读：`dsh plugin` 安装仍可用；`uv`/`uvx` 首次下载 Python、npm 全局缓存等写 `$HOME` 的操作不可用；
- admin 需要写 `/opt/dsh`、`/home/node/.dsh`、`/tmp` 和 npm cache，不支持 `--read-only`；
- 静态 `USER node` 不需要 root 初始化，`--cap-drop=ALL` 不会打断启动（没有 chown/setuid 步骤）。

### 备用镜像（GHCR）

如果从 Docker Hub 拉取受限（如网络问题），可以使用备用镜像（GitHub Container Registry，tag 与 Docker Hub 完全一致）：

```bash
# 拉取 GHCR 上的镜像
docker pull ghcr.io/smanx/deepseek-harness:latest

# 启动命令与默认镜像完全一样，只需替换镜像名
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  ghcr.io/smanx/deepseek-harness:latest
```

> 除镜像地址不同外，两个镜像的配置与使用方式完全一致，可互相替换。

## 配置（环境变量）

| 环境变量 | 含义 | 默认值 |
|---|---|---|
| `DSH_PORT` | 源端口：DSH 在容器内监听（`127.0.0.1`） | `3079` |
| `PROXY_PORT` | 代理端口：代理对外监听（局域网入口） | `3080` |
| `PROXY_USERNAME` | Basic Auth 用户名（可选） | 未设置 |
| `PROXY_PASSWORD` | Basic Auth 密码（可选） | 未设置 |
| `NPM_CONFIG_REGISTRY` | admin 变体管理页「npm 源」的默认值（优先级低于页面配置） | `https://registry.npmjs.org/` |
| `DSH_INSTALL_DIR` | admin 变体 DSH 安装目录（页面安装的 DSH 及状态文件都在这里，建议挂载命名卷） | `/opt/dsh` |

> `DSH_PORT` 与 `PROXY_PORT` 必须不同（同一端口只能被一个进程监听）。
> 修改 `PROXY_PORT` 时，`-p` 端口映射要对应改成 `-p <宿主机端口>:<新代理端口>`。

### 启用 Basic Auth

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

- 用户名和密码**两个都设置**才启用认证；只设置一个（或都不设置）则完全放行；
- 认证对 HTTP 和 WebSocket 都生效，未通过认证返回 `401` + `WWW-Authenticate`，浏览器会弹出认证框；
- 公开静态资源 `/manifest.webmanifest`、`/favicon.svg`、`/favicon.ico` 不参与认证（只含应用名/图标等非敏感数据）。浏览器抓取 `<link rel="manifest">` 时不会携带 Basic Auth 凭据，若强制认证，控制台会持续报 `/manifest.webmanifest` 401。

### 修改代理端口

```bash
# 例如代理对外用 3088
docker run -d \
  --name dsh-harness \
  -p 3088:3088 \
  -v dsh-data:/home/node/.dsh \
  -e PROXY_PORT=3088 \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

## 数据持久化

DSH 的会话/配置数据保存在容器内 `/home/node/.dsh`，上面的命令用命名卷 `dsh-data` 持久化：

- `docker stop/start` 和容器删除后卷仍在，数据不丢；
- 彻底清除数据：`docker volume rm dsh-data`（先停容器）。

如果改用 bind mount，先把宿主目录交给 UID/GID `1000`：

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

## 停止 / 重启 / 删除

```bash
docker stop dsh-harness     # 停止
docker start dsh-harness    # 再次启动
docker logs -f dsh-harness  # 查看日志
docker rm -f dsh-harness    # 删除容器（卷中的数据保留）
```

## 联系作者 / 反馈

- 交流与 Bug 反馈：https://github.com/deepseek-ai/deepseek-harness/discussions/1762
