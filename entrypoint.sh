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
