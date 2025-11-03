#!/usr/bin/env bash
# test_proxies.sh - 并发版
# 用法: ./test_proxies.sh user_list.txt
# 可选: CONCURRENCY=50 ./test_proxies.sh user_list.txt

set -euo pipefail

INPUT=${1:-user_list.txt}
WORKING="working_proxies.txt"
FAILED="failed_proxies.txt"
CONCURRENCY=${CONCURRENCY:-30}   # 并发数，按需调整
TMPDIR=$(mktemp -d)

: > "$WORKING"
: > "$FAILED"

# simple file append lock using mkdir (atomic)
append_locked() {
  local file=$1; shift
  local text="$*"
  while ! mkdir "$TMPDIR/lock.$file" 2>/dev/null; do
    sleep 0.01
  done
  printf '%s\n' "$text" >> "$file"
  rmdir "$TMPDIR/lock.$file"
}

test_one() {
  local line="$1"
  # trim
  line="${line%%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "${line:0:1}" == "#" ]] && return

  # parse: either ip:port:user:pass  OR ip:port
  IFS=':' read -r -a parts <<< "$line"
  if [[ ${#parts[@]} -ge 4 ]]; then
    ip="${parts[0]}"
    port="${parts[1]}"
    user="${parts[2]}"
    pass="${parts[3]}"
    proxy="http://${user}:${pass}@${ip}:${port}"
  elif [[ ${#parts[@]} -eq 2 ]]; then
    proxy="http://${parts[0]}:${parts[1]}"
  else
    append_locked "$FAILED" "$line  # parse_error"
    return
  fi

  # 使用 curl 测试。max-time 总超时，connect-timeout 连接超时
  http_code=$(curl -sS -x "$proxy" --connect-timeout 6 --max-time 12 -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null) || rc=$?
  rc=${rc:-0}

  # 判定：curl 退出码 0 且 http_code < 400 视为成功（200/301/302 都接受）
  if [[ "$rc" -eq 0 && "$http_code" != "" && "$http_code" -lt 400 ]]; then
    append_locked "$WORKING" "$line"
    echo "[OK] $line -> $http_code"
  else
    append_locked "$FAILED" "$line"
    echo "[FAIL] $line -> rc=$rc code=${http_code:-NA}"
  fi
}

# 控制并发的小循环
pids=()
count=0
while IFS= read -r ln || [[ -n "$ln" ]]; do
  test_one "$ln" &

  pids+=($!)
  ((count++))
  if (( count >= CONCURRENCY )); then
    # wait for any to finish
    wait -n
    count=0
  fi
done < "$INPUT"

# wait remaining
wait

rm -rf "$TMPDIR"
echo "完成。成功文件: $WORKING  失败文件: $FAILED"
