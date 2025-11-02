
set -eEuo pipefail
trap 'echo "❌ 出错：第 ${LINENO} 行：命令 [${BASH_COMMAND}]"; exit 1' ERR

# 配置（按需修改）
SQUID_CONF="/etc/squid/squid.conf"
PASSWD_FILE="/etc/squid/passwd"
USER_LIST_FILE="/etc/squid/user_list.txt"
OUTGOING_CONF="/etc/squid/outgoing_map.conf"
PORT=51128
NET_IFACE=""   # 指定网卡名（例如 enp4s0），留空则自动查找所有 scope global IPv4

echo "[*] 清空旧文件（若不想覆盖请先备份）..."
: > "$PASSWD_FILE"
: > "$USER_LIST_FILE"
: > "$OUTGOING_CONF"

# 获取公网 IPv4 地址
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

# 随机密码函数
gen_pwd() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8
}

# 生成用户、密码与配置
for ipaddr in "${IPS[@]}"; do
    user="DD$(gen_pwd)"
    pwd="$(gen_pwd)"

    # 使用更兼容的 hash 生成方式（SHA512 crypt）
    hash="$(openssl passwd -6 "$pwd")"

    echo "${user}:${hash}" >> "$PASSWD_FILE"
    echo "${ipaddr}:${PORT}:${user}:${pwd}" >> "$USER_LIST_FILE"

    acl_name="a_${ipaddr//./_}"
    {
        echo "acl ${acl_name} localip ${ipaddr}"
        echo "tcp_outgoing_address ${ipaddr} ${acl_name}"
        echo ""
    } >> "$OUTGOING_CONF"
done

chmod 600 "$PASSWD_FILE" "$USER_LIST_FILE" "$OUTGOING_CONF"

echo "[+] 完成：生成 ${#IPS[@]} 个用户与对应 ACL/tcp_outgoing_address 规则。"
echo "[+] passwd 文件： $PASSWD_FILE"
echo "[+] outgoing 配置： $OUTGOING_CONF"
echo "[+] 明文用户列表（请妥善保管）： $USER_LIST_FILE"

echo
echo "下一步（必须）:"
echo "1) 检查 $SQUID_CONF 中是否包含："
echo "   include /etc/squid/outgoing_map.conf"
echo "2) 重启 squid:"
echo "   sudo systemctl restart squid"
echo "3) 若 Squid 启动失败，请查看日志： /var/log/squid/cache.log"
