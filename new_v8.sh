#!/bin/bash
set -euo pipefail

# 配置（按需修改）
SQUID_CONF="/etc/squid/squid.conf"
PASSWD_FILE="/etc/squid/passwd"
USER_LIST_FILE="/etc/squid/user_list.txt"
OUTGOING_CONF="/etc/squid/outgoing_map.conf"
PORT=51128
NET_IFACE=""   # 如果你想指定网卡名（例如 eth0），在这里填；留空则自动查找所有 scope global 的 IPv4

# 清理旧文件（谨慎：会覆盖）
echo "[*] 清空旧文件（若不想覆盖请先备份）..."
: > "$PASSWD_FILE"
: > "$USER_LIST_FILE"
: > "$OUTGOING_CONF"

# 获取公网 IPv4 地址列表（可按需改成指定网卡）
if [[ -n "$NET_IFACE" ]]; then
    IPS=($(ip -o -4 addr show dev "$NET_IFACE" scope global | awk '{print $4}' | cut -d/ -f1))
else
    IPS=($(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1))
fi

if [[ ${#IPS[@]} -eq 0 ]]; then
    echo "[!] 未检测到 scope global 的 IPv4 地址，退出。"
    exit 1
fi

echo "[+] 检测到公网 IP 共 ${#IPS[@]} 个"


# 随机密码函数（生成 16 字符的 URL-safe 密码）
gen_pwd() {
    # 使用 /dev/urandom -> base64 -> 删除 +/ -> 取前16
    tr -dc 'A-Za-z0-9!@#%_-+=' < /dev/urandom | head -c 16 || openssl rand -base64 12
}

# 生成用户、passwd 和 outgoing_map.conf

for ipaddr in "${IPS[@]}"; do

    user="DD$(gen_pwd)"
    pwd="$(gen_pwd)"

    # 生成 APR1 (apache-style) hash；openssl 生成的结果形如 $apr1$...
    hash="$(openssl passwd -apr1 "$pwd")"

    # 写入 passwd 文件（username:hash）
    echo "${user}:${hash}" >> "$PASSWD_FILE"

    # 记录明文用户名密码（仅本地保存，注意权限）
    echo "${ipaddr}:${PORT}:${user}:${pwd}" >> "$USER_LIST_FILE"

    # 生成 ACL 名（把点替换为下划线）
    acl_name="a_${ipaddr//./_}"

    # 写入 outgoing_map.conf
    {
        echo "acl ${acl_name} localip ${ipaddr}"
        echo "tcp_outgoing_address ${ipaddr} ${acl_name}"
        echo ""
    } >> "$OUTGOING_CONF"


done

# 设置权限（passwd 与用户列表一定要保护）
chmod 600 "$PASSWD_FILE"
chmod 600 "$USER_LIST_FILE"
chmod 600 "$OUTGOING_CONF"

echo "[+] 完成：生成 ${i} 个用户与对应 ACL/tcp_outgoing_address 规则。"
echo "[+] passwd 文件： $PASSWD_FILE"
echo "[+] outgoing 配置： $OUTGOING_CONF"
echo "[+] 明文用户列表（请妥善保管）： $USER_LIST_FILE"

echo
echo "下一步（必须）:"
echo "1) 检查 $SQUID_CONF 中是否包含："
echo "   include /etc/squid/outgoing_map.conf"
echo "   （若没有，请手动加入或在本脚本中改写 $SQUID_CONF 的生成逻辑）"
echo "2) 重启 squid:"
echo "   sudo systemctl restart squid"
echo "3) 若 Squid 启动失败，请查看日志： /var/log/squid/cache.log 或 systemctl status squid -l"
