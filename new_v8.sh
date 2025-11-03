#!/bin/bash
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
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8 | tr 'A-Z' 'a-z' || true
}

# 生成用户、密码与配置
for ipaddr in "${IPS[@]}"; do
    user="$(gen_pwd)"
    pwd="$(gen_pwd)"

 
    hash="$(openssl passwd -apr1 "$pwd")"

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
chown proxy:proxy /etc/squid/passwd
chmod 640 /etc/squid/passwd

echo "[+] 完成：生成 ${#IPS[@]} 个用户与对应 ACL/tcp_outgoing_address 规则。"
echo "[+] passwd 文件： $PASSWD_FILE"
echo "[+] outgoing 配置： $OUTGOING_CONF"
echo "[+] 明文用户列表（请妥善保管）： $USER_LIST_FILE"

echo "下一步（必须）:"
echo "1) 检查 $SQUID_CONF 中是否包含："
echo "   include /etc/squid/outgoing_map.conf"
# 生成 Squid 配置
cat > "$SQUID_CONF" <<EOF
max_filedescriptors 1048576
workers 8
# client_pconn_limit 16000  # disabled for Squid 3.5
# client_netmask_v4  # disabled for Squid 3.5 0

cache_mem 512 MB
maximum_object_size_in_memory 64 MB
maximum_object_size 512 MB
cache_dir ufs /var/spool/squid 10000 16 256

#access_log none
access_log stdio:/var/log/squid/access.log
cache_log /var/log/squid/cache.log
acl SSL_ports port 443
acl Safe_ports port 80 21 443 70 210 51128 280 488 591 777
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
visible_hostname PI10P65
http_port 0.0.0.0:51128
include /etc/squid/outgoing_map.conf
EOF

echo "[+] Squid 配置生成完毕，请重启 Squid:"
echo "2) 重启 squid:"
echo "   sudo systemctl restart squid"
echo "3) 若 Squid 启动失败，请查看日志： /var/log/squid/cache.log"
