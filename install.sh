#!/usr/bin/env bash
# Wei Yuming 專用：一鍵安裝 XRay + Reality VLESS

set -e

echo "=== XRay + Reality 一鍵部署開始 ==="

if [[ $EUID -ne 0 ]]; then
  echo "請使用 root 權限執行（sudo -i）"
  exit 1
fi

apt update -y
apt install -y curl unzip

echo "安裝 XRay 核心..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

XRAY="/usr/local/bin/xray"
CONF_DIR="/usr/local/etc/xray"
CONF_FILE="$CONF_DIR/config.json"

mkdir -p $CONF_DIR

read -rp "Reality 監聽端口（預設443）：" PORT
PORT=${PORT:-443}

read -rp "偽裝目標域名（例如 www.microsoft.com）：" RDOMAIN
if [[ -z "$RDOMAIN" ]]; then
  echo "偽裝域名不能空"
  exit 1
fi

read -rp "目標端口（預設443）：" RPORT
RPORT=${RPORT:-443}

echo "生成 Reality 密鑰..."
KEY=$($XRAY x25519)
PRIV=$(echo "$KEY" | awk '/Private key/ {print $3}')
PUB=$(echo "$KEY" | awk '/Public key/ {print $3}')

UUID=$(cat /proc/sys/kernel/random/uuid)
SID=$(openssl rand -hex 8)

IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

cat > $CONF_FILE <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "tag": "reality",
    "port": $PORT,
    "listen": "0.0.0.0",
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$RDOMAIN:$RPORT",
        "serverNames": ["$RDOMAIN"],
        "privateKey": "$PRIV",
        "shortIds": ["$SID"]
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

systemctl restart xray

echo "=== 部署完成 ==="
echo
echo "VLESS Reality 節點如下："
echo
echo "vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$RDOMAIN&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#WeiYuming-Reality"
