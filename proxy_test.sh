#!/bin/bash
set -e

# 代理列表路径
PROXY_LIST="./proxy_list.txt"

# 测试目标 URL（返回公网 IP）
TEST_URL="http://ifconfig.me/ip"

# 超时时间（秒）
TIMEOUT=5

# 输出结果文件
RESULT_FILE="./proxy_check_result.txt"
> "$RESULT_FILE"

if [ ! -f "$PROXY_LIST" ]; then
    echo "未找到代理列表文件：$PROXY_LIST"
    exit 1
fi

echo "开始检查代理是否可用..."
while IFS=: read -r IP PORT USER PASS; do
    # 使用 curl 测试代理
    RESPONSE=$(curl -s --max-time $TIMEOUT --proxy "http://${USER}:${PASS}@${IP}:${PORT}" "$TEST_URL" || echo "FAIL")
    if [[ "$RESPONSE" == "FAIL" || -z "$RESPONSE" ]]; then
        STATUS="FAIL"
    else
        STATUS="OK"
    fi
    echo "${IP}:${PORT} -> ${STATUS} (${RESPONSE})" | tee -a "$RESULT_FILE"
done < "$PROXY_LIST"

echo "检查完成，结果保存到：$RESULT_FILE"
