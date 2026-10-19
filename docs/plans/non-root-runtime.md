# 非 root 运行方案（node 用户，UID/GID 1000）

本文只描述目标状态与实施步骤。

## 1. 目标与范围

**目标**

- 5 个变体（latest、devtools-min、devtools、test、admin）默认以 `node` 用户运行。
- `node` 用户 UID/GID `1000:1000`；HOME `/home/node`；DSH 数据目录 `/home/node/.dsh`。
- 静态 `USER node`：PID 1 与所有应用进程都是 node，不使用 gosu/su-exec。
- 只保留必要的可写路径：`/home/node/.dsh`、`/tmp`、`/opt/dsh`（admin）。
- 代码与工具链保持只读：`/app`、`/usr/local` 为 `root:root 0755`。

**范围**

- `Dockerfile`、`entrypoint.sh`、`manager/index.js`、`proxy/upstream-token.js`、`.build-variants`。
- 四份仓库文档与本文。
- 5 个变体的构建/运行命令与验证矩阵。

**不在范围**

- 宿主 rootless Docker / Podman。
- 非 Docker 部署方式。
- 实际代码修改、构建与发布（本文是实施方案）。

**假设**

- 基础镜像 `node:24-slim`（Debian 12 bookworm-slim）。
- Linux Engine，amd64/arm64；命名卷；Docker 默认 seccomp。
- `node` 用户已存在：UID/GID 1000、home `/home/node`、shell `/bin/bash`。

## 2. 已锁定决策

| 项 | 目标状态 |
|---|---|
| 运行用户 | `node`，UID/GID `1000:1000` |
| HOME | `/home/node` |
| DSH_HOME | `/home/node/.dsh` |
| `/app` | `root:root 0755`，只读+执行 |
| `/usr/local` | `root:root 0755`，只读+执行 |
| `/opt/dsh` | `1000:1000`，仅 admin 需要可写 |
| 日志/token | `/tmp/.dsh-web.log`、`/tmp/.dsh-launch-token`，`umask 077` / `0600` |
| 数据卷 | `dsh-data:/home/node/.dsh` |
| 安装卷 | `dsh-install:/opt/dsh`（仅 admin） |
| bind mount | 固定 UID/GID 1000；宿主目录先 `chown -R 1000:1000` |
| pnpm | `12.14.0`，所有变体内置（构建期 root 安装，运行期只读+执行） |
| test 预装插件 | 构建期以 `node` 用户执行 `dsh plugin`，profile 归 node |
| git | devtools-min/devtools/test/admin（admin 另含运行期编译工具）；`github:` 插件需带 git 的变体 |
| admin 与 read-only | admin 不支持 `--read-only`；latest/devtools-min/devtools/test 支持 |
| 文档 | 只描述目标状态；README_EN/DOCKERHUB.en 同步；方案文档中文 |

## 3. 逐文件目标配置

### 3.1 Dockerfile

目标结构如下（省略与用户/权限无关的上下文，保留关键行）：

```dockerfile
ARG PNPM_VERSION=12.14.0

# ── 构建阶段：安装 DSH；admin 变体预装到 /opt/dsh ──────────────
FROM node:24-slim AS dsh-builder
ARG DEV_TOOLS=none
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/* \
 && if [ "$DEV_TOOLS" = "admin" ]; then \
      npm install -g --prefix /opt/dsh --no-audit --no-fund @deepseek-ai/dsh@next; \
    else \
      npm install -g --no-audit --no-fund @deepseek-ai/dsh@next; \
    fi \
 && mkdir -p /opt/dsh

# ── 运行阶段 ───────────────────────────────────────────────────
FROM node:24-slim
ARG DEV_TOOLS=none
ARG PNPM_VERSION
WORKDIR /app

# Node + DSH 全局包：/usr/local 保持 root-owned
COPY --from=dsh-builder /usr/local/ /usr/local/

# admin 的预装 DSH 目录：归 node；非 admin 变体是空目录，归 node 无害
COPY --chown=1000:1000 --from=dsh-builder /opt/dsh/ /opt/dsh/

# 必须可写的目录：/opt/dsh（admin 安装）、/home/node/.dsh（DSH 数据）
RUN install -d -m 0755 -o node -g node /opt/dsh /home/node/.dsh

# 版本文件（CI 打 tag 用）
RUN if [ "$DEV_TOOLS" = "admin" ]; then \
      node -p "'APP_VERSION=' + require('/opt/dsh/lib/node_modules/@deepseek-ai/dsh/package.json').version" > /tmp/app_version.env; \
    else \
      node -p "'APP_VERSION=' + require('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json').version" > /tmp/app_version.env; \
    fi

# 代理与管理服务：/app 保持 root-owned
COPY proxy/ /app/proxy/
RUN cd /app/proxy && npm install --omit=dev --no-audit --no-fund

COPY manager/ /app/manager/
RUN cd /app/manager && npm install --omit=dev --no-audit --no-fund

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# admin 变体标记
RUN if [ "$DEV_TOOLS" = "admin" ]; then touch /app/.admin-mode; fi

# 开发工具：apt / npm 全局包 / uv，构建期 root
COPY .build-variants /app/.build-variants
RUN if [ -n "$DEV_TOOLS" ] && [ "$DEV_TOOLS" != "none" ]; then \
      PACKAGES="$(awk -F'|' -v p="$DEV_TOOLS" '$1==p {print $2}' /app/.build-variants)"; \
      NPM_PKGS="$(awk -F'|' -v p="$DEV_TOOLS" '$1==p {print $3}' /app/.build-variants)"; \
      UV_FLAG="$(awk -F'|' -v p="$DEV_TOOLS" '$1==p {print $4}' /app/.build-variants)"; \
      if [ -n "$PACKAGES" ]; then \
        apt-get update && apt-get install -y --no-install-recommends $PACKAGES \
        && rm -rf /var/lib/apt/lists/*; \
      fi; \
      if [ -n "$NPM_PKGS" ]; then npm install -g --no-audit --no-fund $NPM_PKGS; fi; \
      if [ "$UV_FLAG" = "1" ]; then \
        curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh; \
      fi; \
    fi

# pnpm：所有变体统一 pin 版本；构建期 root，运行期 node 只读+执行
RUN npm install -g --no-audit --no-fund pnpm@${PNPM_VERSION}

# test 变体：以 node 用户预装插件，profile 直接归 node
RUN if [ "$DEV_TOOLS" = "test" ]; then \
      command -v runuser >/dev/null 2>&1 || { echo "runuser missing"; exit 1; }; \
      runuser -u node -- env HOME=/home/node \
        DSH_HOME=/home/node/.dsh \
        PNPM_HOME=/home/node/.local/share/pnpm \
        PATH=/usr/local/bin:$PATH \
        dsh plugin --profile web add github:smanx/dsh-fixed-providers#master; \
    fi

# 运行期环境：HOME / DSH 路径 / 日志与 token
ENV HOME=/home/node \
    DSH_HOME=/home/node/.dsh \
    DSH_WEB_LOG=/tmp/.dsh-web.log \
    DSH_TOKEN_FILE_AUTO=/tmp/.dsh-launch-token \
    SHELL=/bin/bash

# 关键：静态 USER node，放在所有 root 操作之后
USER node

EXPOSE 3080
ENTRYPOINT ["/app/entrypoint.sh"]
```

约束：

- 不要使用 `RUN chown -R /usr/local` 或 `RUN chown -R /app`：前者让工具链可写，后者让代码可写，且会增大镜像。
- 不要加 `--omit=optional` 或 `--ignore-scripts`：`koffi` 的 linux 预编译来自 optionalDependency，跳过会让 node-pty/koffi 退化到源码编译。
- `/opt/dsh` 只做 `COPY --chown` + 非递归 `install -d`；空 `dsh-install` 卷首次挂载会继承 node 属主。
- `/home/node/.dsh` 由 `install -d` 创建并归 node；空 `dsh-data` 卷首次挂载会继承 node 属主。
- `USER node` 之后不能再执行 apt/npm 全局安装/chown；所有构建期操作放在它之前。

### 3.2 entrypoint.sh

```sh
#!/bin/sh
set -e

# 日志/token 默认 0600
umask 077

# admin 变体：管理服务接管
if [ -f /app/.admin-mode ]; then
  echo "[admin] 启动 DSH 管理服务 ..."
  exec node /app/manager/index.js
fi

DSH_PORT="${DSH_PORT:-3079}"
PROXY_PORT="${PROXY_PORT:-3080}"

# 日志与 launch token 都放 /tmp；env 优先，代码里有同名默认
: "${DSH_WEB_LOG:=/tmp/.dsh-web.log}"
: "${DSH_TOKEN_FILE_AUTO:=/tmp/.dsh-launch-token}"

# 启动 DSH（只监听 127.0.0.1）
echo "[dsh] 启动 DSH (dsh web --port $DSH_PORT) ..."
dsh web --port "$DSH_PORT" > "$DSH_WEB_LOG" 2>&1 &
DSH_PID=$!
tail -f "$DSH_WEB_LOG" &

# 等待就绪（最多 120 秒）
ready=0
i=0
while [ "$i" -lt 120 ]; do
  if node -e "fetch('http://127.0.0.1:$DSH_PORT/').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$DSH_PID" 2>/dev/null; then
    echo "[dsh] 错误：DSH 进程已退出"
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

if [ "$ready" != "1" ]; then
  echo "[dsh] 错误：DSH 120 秒内未就绪"
  exit 1
fi

cleanup() {
  echo "[proxy] 收到退出信号，停止 DSH ..."
  kill "$DSH_PID" 2>/dev/null || true
  wait "$DSH_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[proxy] 启动代理：0.0.0.0:$PROXY_PORT -> 127.0.0.1:$DSH_PORT"
cd /app/proxy
exec node index.js
```

约束：

- `umask 077` 让 `/tmp` 日志与 token 为 0600；token 文件另在代码里显式 `mode: 0o600`。
- 不再写 `/app`；`/app` 保持 root-owned。
- `dsh` 通过 `/usr/local/bin`（latest/devtools/test）或 `/opt/dsh/bin`（admin manager 设置 PATH）执行，node 有执行权限。

### 3.3 manager/index.js

目标行为：

- `DSH_WEB_LOG = process.env.DSH_WEB_LOG || '/tmp/.dsh-web.log'`。
- `INSTALL_DIR = process.env.DSH_INSTALL_DIR || '/opt/dsh'`。
- `MANAGER_DIR = /opt/dsh/manager`；`STATE_FILE = /opt/dsh/manager/state.json`；由 node 创建/写入。
- `installDsh`：`npm install -g --prefix /opt/dsh --no-audit --no-fund @deepseek-ai/dsh@<version>`；环境带 `NPM_CONFIG_REGISTRY`；npm cache 在 `~/.npm`。
- `saveState()`：`mkdirSync(MANAGER_DIR, { recursive: true })` 后写 `state.json`；node 对 `/opt/dsh` 可写。
- `bootDsh()`：`spawn(DSH_BIN, ['web', '--port', DSH_PORT])`，env 继承 `HOME`、`DSH_HOME`，`PATH` 前置 `/opt/dsh/bin`；日志流写 `DSH_WEB_LOG`（`/tmp`）。
- `stopDsh()`：SIGTERM，10 秒后 SIGKILL；DSH 是 manager 子进程，node 有权限 kill。
- `waitDshReady()`：轮询 `127.0.0.1:<port>`；不变。
- 不写 `/usr/local`；不 chown；不需要 root。

### 3.4 proxy/upstream-token.js

目标行为：

- `LOG_FILE = process.env.DSH_WEB_LOG || '/tmp/.dsh-web.log'`。
- `TOKEN_FILE_AUTO = process.env.DSH_TOKEN_FILE_AUTO || '/tmp/.dsh-launch-token'`。
- 写 token 时使用 `{ mode: 0o600 }`；文件已存在时 `fs.chmodSync` 兜底。
- 其余打捞/重发逻辑不变；不写安装目录。
- `proxy/index.js` 只负责 HTTP/WS 转发与 HTML 注入，不需要路径改动。

### 3.5 .build-variants

目标：移除 `pnpm` 列，pnpm 由 Dockerfile 统一 pin 安装。

```text
test|git curl wget nano jq procps ca-certificates unzip vim openssh-client zip htop tmux tree openssl python3 build-essential bash-completion||1
admin|git curl wget nano jq procps ca-certificates unzip vim openssh-client zip htop tmux tree openssl python3 build-essential bash-completion||1
devtools|git curl wget nano jq procps ca-certificates unzip vim openssh-client zip htop tmux tree openssl python3 build-essential bash-completion||1
devtools-min|git curl wget nano jq procps ca-certificates unzip||1
```

第三列（npm 全局包）为空；`pnpm` 由 `ARG PNPM_VERSION=12.14.0` 统一安装。`uv` 标记保持 `1`。

### 3.6 四份文档

`README.md`、`README_EN.md`、`DOCKERHUB.md`、`DOCKERHUB.en.md` 的目标内容：

- 运行命令使用 `-v dsh-data:/home/node/.dsh`；admin 使用 `-v dsh-data:/home/node/.dsh -v dsh-install:/opt/dsh`。
- 数据持久化路径 `/home/node/.dsh`。
- `docker exec` 默认 node；`docker exec -u 0` 仅紧急排障。
- bind mount 宿主目录先 `chown -R 1000:1000`。
- pnpm `12.14.0` 已内置所有变体；dsh-market 不再需要自动安装 pnpm；`github:` 插件需要带 git 的变体。
- 可选加固单独一节（见 §4.3）。
- 只描述目标状态；不写旧路径、旧命令、迁移/回滚、历史或“破坏性变更”章节。
- README_EN / DOCKERHUB.en 与中文同步。

## 4. 精确命令

### 4.1 构建

```bash
# latest
docker build -t smanx/deepseek-harness:latest .

# devtools-min
docker build -t smanx/deepseek-harness:devtools-min-latest --build-arg DEV_TOOLS=devtools-min .

# devtools
docker build -t smanx/deepseek-harness:devtools-latest --build-arg DEV_TOOLS=devtools .

# test
docker build -t smanx/deepseek-harness:test-latest --build-arg DEV_TOOLS=test .

# admin
docker build -t smanx/deepseek-harness:admin-latest --build-arg DEV_TOOLS=admin .
```

版本 tag 由 CI 读取 `/tmp/app_version.env` 的 `APP_VERSION` 追加，例如 `latest` → `<version>`、`devtools-latest` → `devtools-<version>`。

### 4.2 运行

**latest / devtools-min / devtools / test（命名卷）**

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:latest
```

**admin（两个命名卷）**

```bash
docker run -d \
  --name dsh-harness \
  -p 3080:3080 \
  -v dsh-data:/home/node/.dsh \
  -v dsh-install:/opt/dsh \
  --restart unless-stopped \
  smanx/deepseek-harness:admin-latest
```

**bind mount**

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

命名卷不受宿主 UID 影响；bind mount 由宿主权限决定，固定要求 UID/GID 1000。

### 4.3 可选加固

```bash
# 最小权限 + 禁止提权（所有变体）
docker run ... \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  smanx/deepseek-harness:latest

# 只读 rootfs（latest/devtools-min/devtools/test；admin 不支持）
docker run ... \
  --read-only \
  --tmpfs /tmp:rw,exec,size=64m \
  -v dsh-data:/home/node/.dsh \
  smanx/deepseek-harness:latest
```

说明：

- `--read-only` 只读 rootfs，volume/tmpfs 仍可写；需要 `--tmpfs /tmp` 放日志/token/临时文件。
- tmpfs 必须显式带 `exec`：Docker 的 tmpfs 默认 `noexec`，而 DSH 会把原生绑定复制到 `/tmp` 再加载，缺 `exec` 时启动报 `No usable native binding`。
- 不要在 `/tmp` 上加 `noexec`：DSH 会在 `/tmp` 写 shell 集成脚本与原生绑定缓存，`noexec` 会让工具执行/启动失败。
- `--read-only` 下 `$HOME` 除 `/home/node/.dsh` 卷外只读：页面、会话与 `dsh plugin` 安装（pnpm store 在 `.dsh` 卷内）可用；`uv`/`uvx` 首次下载 Python、npm 全局缓存等写 `$HOME` 的操作不可用，需要时给对应目录额外挂 tmpfs/卷。
- admin 需要写 `/opt/dsh`、`/home/node/.dsh`、`/tmp`、npm cache，不支持 `--read-only`。
- `--cap-drop=ALL` 与静态 `USER node` 兼容；不需要 root 初始化，所以不会打断 chown/setuid。

### 4.4 `docker exec`

```bash
docker exec dsh-harness id          # uid=1000(node)
docker exec -u 0 dsh-harness id     # uid=0，仅紧急排障
```

默认用户来自镜像 `USER node`；`-u 0` 只是有 Docker API 权限的操作者的紧急逃生口，不属于正常运行路径。

## 5. 验证矩阵

### 5.1 构建矩阵

| 变体 | build-arg | 目标 tag |
|---|---|---|
| latest | 无 | `latest` / `<version>` |
| devtools-min | `DEV_TOOLS=devtools-min` | `devtools-min-latest` / `devtools-min-<version>` |
| devtools | `DEV_TOOLS=devtools` | `devtools-latest` / `devtools-<version>` |
| test | `DEV_TOOLS=test` | `test-latest` / `test-<version>` |
| admin | `DEV_TOOLS=admin` | `admin-latest` / `admin-<version>` |

### 5.2 非 root 断言

| 检查 | 命令 | 通过标准 |
|---|---|---|
| 默认用户 | `docker exec <ct> id` | `uid=1000(node) gid=1000(node)` |
| 进程树 | `docker top <ct>` / `docker exec <ct> ps -eo user,pid,args` | 无 root 进程 |
| PID 1 | `docker exec <ct> cat /proc/1/status` | `Uid: 1000 1000 1000 1000` |
| 关键目录属主 | `docker exec <ct> stat -c '%u:%g %a %n' /app /usr/local /opt/dsh /home/node/.dsh` | `/app`、`/usr/local` = `0:0 755`；`/opt/dsh`、`/home/node/.dsh` = `1000:1000` |
| 安装目录只读 | `docker exec -u 0 <ct> chmod -R a-w /usr/local/lib/node_modules/@deepseek-ai/dsh` 后重启 DSH | DSH 仍能启动 |
| 不可写断言 | `docker exec <ct> touch /app/x /usr/local/x` | Permission denied |
| 可写断言 | `docker exec <ct> touch /home/node/.dsh/x` | 成功 |
| 紧急 root | `docker exec -u 0 <ct> id` | uid=0（仅紧急路径） |

说明：

- `latest` 不装 `procps`，进程断言用宿主 `docker top <ct>`。
- admin 的 DSH 在 `/opt/dsh` 安装卷且必须可写，安装目录只读断言仅适用于非 admin 变体。

### 5.3 冒烟矩阵

| 变体 | 必测 |
|---|---|
| latest | 页面、WS、Basic Auth、持久化重启、registry 插件安装、pnpm、node-pty、沙箱/工具执行、可选 `--read-only` |
| devtools-min | latest 全部 + uv、git、bind mount |
| devtools | devtools-min 全部 + `python3/make/g++` 编译 |
| test | devtools 全部 + 预装插件 profile 属主 node、空卷复制/非空卷遮蔽 |
| admin | 页面、WS、Basic Auth、持久化、两卷、安装/切换版本、重启、插件、pnpm、node-pty（其它架构编译）；**不支持 `--read-only`** |

### 5.4 通过标准

- 每个变体：默认用户 node、PID 1 node、关键目录属主正确、页面/WS 可用、数据在 `/home/node/.dsh`、无 root 进程。
- admin：两个卷都非 `:ro`；`state.json` 可写；安装/切换/重启成功；不能加 `--read-only`。
- latest：不装 git；`github:` 插件需带 git 的变体。
- bind mount：宿主目录 `chown -R 1000:1000`；Docker Desktop/rootless 的 UID 映射需实测。
- MCP/uvx 真实会话：可选加项，不计入 pass/fail。

### 5.5 失败诊断

- **EACCES**：检查目录/卷属主、`HOME`、`DSH_HOME`、`/tmp`、npm cache。
- **`runuser` 缺失**：test 构建期插件安装失败；改用 `su node -s /bin/bash -c ...` 或 root + `chown -R node:node /home/node`。
- **pnpm 缺失**：`dsh plugin` 退出 127；检查 `/usr/local/bin/pnpm` 与 `ARG PNPM_VERSION`。
- **沙箱 fail-closed**：`bwrap`/`landlock` 不可用时 `workspace-write` 的 bash 工具失败；先确认内核 Landlock 或装 bubblewrap；`DSH_PERMISSION_MODE=danger-full-access` 仅排障。
- **`--read-only` 失败**：先确认 `/tmp` tmpfs 带 `exec`（Docker 默认 `noexec`，缺它会报 `No usable native binding`），再确认 `/home/node/.dsh` 卷、admin 的 `/opt/dsh` 卷；admin 直接不支持 read-only。
- **node-pty 失败**：确认 `/dev/ptmx`、`/dev/pts`；其它架构确认 `python3/make/g++` 与 `~/.cache/node-gyp`。

## 6. 已知限制与不在范围

**已知限制**

- admin 变体不支持 `--read-only`（需要写 `/opt/dsh`、`/home/node/.dsh`、`/tmp`、npm cache）。
- latest 变体不装 git；`github:` 插件需要带 git 的变体（devtools-min/devtools/test/admin）。
- bind mount 固定 UID/GID 1000；宿主 UID 不是 1000 时用命名卷或 `chown`。
- Docker Desktop / userns-remap / rootless 的 UID 映射与 Linux Engine 不同，需在目标平台实测。
- pnpm store / uv Python 下载在 HOME 下，不持久化；容器重建后可重建。`--read-only` 模式只有 DSH_HOME 卷可写，uv/uvx 首次下载 Python 等写 HOME 的操作不可用。
- MCP/uvx 真实会话回归为可选加项。

**不在范围**

- 宿主 rootless Docker / Podman / 以非 root 运行 docker CLI。
- 实际代码修改、构建、发布。
- 非 Docker 部署方式。
