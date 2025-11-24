#!/usr/bin/env bash
# Wei Yuming 專用：一鍵安裝 XRay + Reality VLESS（修正版）

set -e

echo "=== XRay + Reality 一鍵部署開始（修正版） ==="

# 0. 基礎檢查
if [[ $EUID -ne 0 ]]; then
  echo "請使用 root 權限執行（sudo -i）"
  exit 1
fi

apt update -y
apt install -y curl unzip -qq

# 1. 安裝 / 更新 XRay
echo "安裝 / 更新 XRay 核心..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

XRAY="/usr/local/bin/xray"
CONF_DIR="/usr/local/etc/xray"
CONF_FILE="$CONF_DIR/config.json"

mkdir -p "$CONF_DIR"

# 2. 互動式輸入
read -rp "Reality 監聽端口（預設443）： " PORT
PORT=${PORT:-443}

read -rp "偽裝目標域名（例如 www.microsoft.com）： " RDOMAIN
if [[ -z "$RDOMAIN" ]]; then
  echo "❌ 偽裝域名不能空，腳本終止。"
  exit 1
fi

read -rp "目標端口（預設443）： " RPORT
RPORT=${RPORT:-443}

# 3. 生成 Reality 密鑰（這裡是修正重點）
echo "生成 Reality x25519 密鑰..."
KEY_OUTPUT="$($XRAY x25519 2>/dev/null || true)"

PRIV=$(echo "$KEY_OUTPUT" | grep "Private key" | sed 's/.*Private key: *//')
PUB=$(echo "$KEY_OUTPUT"  | grep "Public key"  | sed 's/.*Public key: *//')

if [[ -z "$PRIV" || -z "$PUB" ]]; then
  echo "❌ 無法正確取得 Reality 密鑰（privateKey / publicKey 為空），請手動執行："
  echo "    $XRAY x25519"
  echo "再把結果貼給我，我幫你改 config.json。"
  exit 1
fi

# 備份一份在本機，方便以後查看
echo "Reality Private key: $PRIV" > /root/reality-keys.txt
echo "Reality Public  key: $PUB" >> /root/reality-keys.txt

UUID=$(cat /proc/sys/kernel/random/uuid)
SID=$(openssl rand -hex 8)

# 4. 自動偵測伺服器 IP
IP=$(
  curl -s ipv4.ip.sb || \
  curl -s ifconfig.me || \
  hostname -I | awk '{print $1}'
)

if [[ -z "$IP" ]]; then
  IP="YOUR_SERVER_IP"
fi

echo
echo "=== 生成參數 ==="
echo "監聽端口：$PORT"
echo "偽裝域名：$RDOMAIN"
echo "目標端口：$RPORT"
echo "UUID：$UUID"
echo "Reality PrivateKey：$PRIV"
echo "Reality PublicKey ：$PUB"
echo "ShortID：$SID"
echo "伺服器 IP：$IP"
echo "================"
echo

# 5. 寫入 XRay Reality 配置
cat > "$CONF_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "reality-in",
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$RDOMAIN:$RPORT",
          "xver": 0,
          "serverNames": ["$RDOMAIN"],
          "privateKey": "$PRIV",
          "shortIds": ["$SID"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
EOF

# 6. 重啟 XRay
echo "重啟 XRay 服務..."
systemctl daemon-reload
systemctl restart xray

sleep 1
if systemctl is-active --quiet xray; then
  echo "✅ XRay 已啟動成功。"
else
  echo "❌ XRay 啟動失敗，請執行：journalctl -u xray -e --no-pager | tail -n 30 檢查。"
  exit 1
fi

# 7. 輸出 vless Reality 節點
VLESS_LINK="vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$RDOMAIN&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#WeiYuming-Reality"

echo
echo "=== 部署完成 ==="
echo "VLESS Reality 節點如下："
echo "$VLESS_LINK"
echo
echo "已備份 Reality 密鑰到：/root/reality-keys.txt"
