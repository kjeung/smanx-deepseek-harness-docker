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
