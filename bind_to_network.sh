#!/bin/bash
set -euo pipefail

# 你的网卡
IFACE="enp3s0"

# 所有网段
RANGES=(
194.143.222.0/24
194.60.90.0/24
194.93.62.0/24
195.114.203.0/24
198.1.239.0/24
198.1.240.0/24
198.1.241.0/24
209.87.172.0/24
213.139.67.0/24
216.97.228.0/24
216.97.235.0/24
31.14.37.0/24
40.183.224.0/24
40.183.225.0/24
40.183.230.0/24
40.183.231.0/24
40.223.245.0/24
45.11.173.0/24
45.155.241.0/24
45.39.168.0/24
45.42.43.0/24
45.42.46.0/24
45.59.106.0/24
50.2.48.0/24
64.188.14.0/24
64.188.19.0/24
)

echo "开始永久写入 IP 到 NetworkManager 配置..."

for range in "${RANGES[@]}"; do
  ip_base=$(echo "$range" | cut -d/ -f1)
  mask=$(echo "$range" | cut -d/ -f2)

  IFS=. read -r a b c d <<< "$ip_base"

  echo "处理网段: $range"

  # /24 段
  if [ "$mask" = "24" ]; then
    for i in $(seq 1 254); do
      ip="${a}.${b}.${c}.${i}"
      nmcli con mod "$IFACE" +ipv4.addresses "${ip}/32"
    done
  fi

  # /22 段
  if [ "$mask" = "22" ]; then
    for c2 in $(seq $c $((c+3))); do
      for i in $(seq 1 254); do
        ip="${a}.${b}.${c2}.${i}"
        nmcli con mod "$IFACE" +ipv4.addresses "${ip}/32"
      done
    done
  fi
done

echo "重新加载网卡..."
nmcli con down "$IFACE" || true
nmcli con up "$IFACE"

echo ""
echo "绑定完成（永久有效）。"
echo "当前绑定数量：$(ip -4 addr show dev $IFACE | grep -c 'inet ')"
