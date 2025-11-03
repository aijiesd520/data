cat > test_proxies_fast.sh <<'EOF'
#!/usr/bin/env bash
# test_proxies_fast.sh - 快速并发检测代理是否能访问网络
# 用法:
#   chmod +x test_proxies_fast.sh
#   CONCURRENCY=200 PROXY_TYPE=http TARGET_URL=https://example.com ./test_proxies_fast.sh user_list.txt
#
# 环境变量说明（可在命令行覆盖）:
#   CONCURRENCY     - 并发数，默认 200
#   PROXY_TYPE      - http (默认) 或 socks5h
#   CONNECT_TIMEOUT - curl 连接超时（秒），默认 3
#   MAX_TIME        - curl 最大总超时（秒），默认 6
#   TARGET_URL      - 测试目标，默认 https://example.com
#
set -euo pipefail

INPUT=${1:-user_list.txt}
CONCURRENCY=${CONCURRENCY:-200}
PROXY_TYPE=${PROXY_TYPE:-http}   # http 或 socks5h
CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-3}
MAX_TIME=${MAX_TIME:-6}
TARGET_URL=${TARGET_URL:-https://example.com}

WORKING="working_proxies.txt"
FAILED="failed_proxies.txt"
TMP_LOG="./.test_proxies_fast.log"

: > "$WORKING"
: > "$FAILED"
: > "$TMP_LOG"

if [[ ! -f "$INPUT" ]]; then
  echo "输入文件不存在: $INPUT"
  exit 2
fi

# 过滤掉空行和注释，交给 xargs 并发处理
# Each worker gets one line like "ip:port:user:pass" or "ip:port"
# Use xargs to spawn up to CONCURRENCY bash workers
export CONCURRENCY PROXY_TYPE CONNECT_TIMEOUT MAX_TIME TARGET_URL WORKING FAILED TMP_LOG

# Worker bash - parse and test one line
worker_script='
line="$1"
# trim CR and spaces
line="${line%%$'\''\r'\''}"
line="${line#"${line%%[![:space:]]*}"}"
line="${line%"${line##*[![:space:]]}"}"
[[ -z "$line" || "${line:0:1}" == "#" ]] && exit 0

# parse into parts (ip:port[:user:pass])
IFS=":" read -r a b c d extra <<< "$line"

if [[ -n "$d" ]]; then
  # have user:pass (we ignore extra beyond 4 fields)
  user="$c"
  pass="$d"
  proxy="${PROXY_TYPE}://${user}:${pass}@${a}:${b}"
else
  proxy="${PROXY_TYPE}://${a}:${b}"
fi

# Run curl; capture exit code and http code
http_code=$(curl -sS -x "$proxy" --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" -o /dev/null -w "%{http_code}" "$TARGET_URL" 2>/dev/null) || rc=$?
rc=${rc:-0}

# Decide success: curl exit 0 and http_code < 400
if [[ "$rc" -eq 0 && "$http_code" != "" && "$http_code" -lt 400 ]]; then
  printf "%s\n" "$line" >> "$WORKING"
  printf "[OK] %s -> %s\n" "$line" "$http_code" >> "$TMP_LOG"
else
  printf "%s\n" "$line" >> "$FAILED"
  printf "[FAIL] %s -> rc=%s code=%s\n" "$line" "${rc:-NA}" "${http_code:-NA}" >> "$TMP_LOG"
fi
'

# run with xargs - parallel
# Use -r to not run if no input
# -n1 one argument per command; -P concurrency
cat "$INPUT" \
  | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//" \
  | sed '/^\s*#/d;/^\s*$/d' \
  | xargs -r -n1 -P "$CONCURRENCY" bash -c "$worker_script" _

# show summary
echo "检测完成。统计："
wc -l "$WORKING" "$FAILED" 2>/dev/null || true
echo "部分输出日志（最后 30 行）:"
tail -n 30 "$TMP_LOG" || true
EOF

chmod +x test_proxies_fast.sh
