#!/bin/bash
set -euo pipefail

IFACE="enp3s0"
CFG="/etc/network/interfaces.d/${IFACE}-ips.cfg"

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

echo "生成永久 IP 配置: $CFG"
echo "# 自动生成的附加IP" > "$CFG"
echo "iface $IFACE inet static" >> "$CFG"
echo "    address 0.0.0.0" >> "$CFG"
echo "    netmask 255.255.255.255" >> "$CFG"

IDX=0

for range in "${RANGES[@]}"; do
  ip_base=$(echo "$range" | cut -d/ -f1)
  mask=$(echo "$range" | cut -d/ -f2)
  IFS=. read -r a b c d <<< "$ip_base"

  if [ "$mask" = "24" ]; then
    for i in $(seq 1 254); do
      ip="${a}.${b}.${c}.${i}"
      echo "    up ip addr add ${ip}/32 dev $IFACE" >> "$CFG"
      IDX=$((IDX+1))
    done
  fi

done

echo "生成完毕：共 $IDX 个 IP 已写入 $CFG"
echo ""
echo "重启网络以应用： systemctl restart networking"
