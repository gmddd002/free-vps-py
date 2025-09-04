#!/bin/bash
# =========================================
# 自控闭环版一键部署脚本（最终版）
# Author: gmddd002
# Repo:   https://github.com/gmddd002/free-vps-py
# Project:https://github.com/gmddd002/python-xray-argo
# =========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
LOGFILE="app.log"

echo -e "${GREEN}>>> 开始部署（闭环版）...${NC}" | tee -a "$LOGFILE"

# 检查 root 权限
if [ "$(id -u)" -eq 0 ]; then
    echo "检测到 root 用户，使用 apt-get 安装依赖..."
    apt-get update
    apt-get install -y python3 python3-pip curl jq git unzip
else
    echo "非 root 环境，跳过 apt-get，使用 pip 安装 Python 依赖"
    pip3 install --user requests psutil
fi

# 安装 cloudflared
if ! command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}安装 cloudflared（Argo 客户端）...${NC}" | tee -a "$LOGFILE"
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o cloudflared
    chmod +x cloudflared
    mkdir -p $HOME/.local/bin
    mv cloudflared $HOME/.local/bin/
    export PATH="$HOME/.local/bin:$PATH"
fi

# 克隆项目
cd $HOME
rm -rf python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git
cd python-xray-argo
pip3 install --user -r requirements.txt

# 分配端口
while true; do
  PORT=$(python3 - <<'PYCODE'
import socket, random
while True:
    port = random.randint(20000, 29999)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        if s.connect_ex(('localhost', port)) != 0:
            print(port)
            break
PYCODE
)
  [ -n "$PORT" ] && break
done
export PORT

# 启动 app.py
echo -e "${GREEN}>>> 启动 Xray-Argo 应用...${NC}" | tee -a "$LOGFILE"
nohup python3 app.py > "$LOGFILE" 2>&1 &
MAIN_PID=$!

# 保活进程
(
while true; do
    sleep 10
    if ! ps -p $MAIN_PID > /dev/null; then
        echo "$(date) 服务掉线，正在重启..." >> keepalive.log
        nohup python3 app.py >> "$LOGFILE" 2>&1 &
        MAIN_PID=$!
    fi
done
) &

KEEPALIVE_PID=$!

# 等待启动
sleep 15

# 获取隧道域名
ARGO_ADDR=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOGFILE" | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}

# 订阅与节点
SUB_B64=$(cat sub.txt 2>/dev/null || echo "")
DECODED_LINKS=$(echo "$SUB_B64" | base64 -d 2>/dev/null || echo "")

VLESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vless://[^ ]+' | head -n1)
VMESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vmess://[^ ]+' | head -n1)
TROJAN_URI=$(echo "$DECODED_LINKS" | grep -oE 'trojan://[^ ]+' | head -n1)
UUID=$(echo "$VLESS_URI" | grep -oP '(?<=vless://)[0-9a-fA-F-]{36}')
SNI=$(echo "$VLESS_URI" | grep -oP '(?<=&sni=)[^&]+')
HOST=$(echo "$VLESS_URI" | grep -oP '(?<=&host=)[^&]+')

# 输出信息
echo "========================================"
echo "                  部署完成！             "
echo "========================================"
echo
echo "=== 服务信息 ==="
echo "服务状态: 运行中"
echo "主服务PID: $MAIN_PID"
echo "保活服务PID: $KEEPALIVE_PID"
echo "服务端口: $PORT"
echo "UUID: $UUID"
echo "订阅路径: /sub"
echo
echo "=== 访问地址 ==="
echo "订阅地址: http://$ARGO_ADDR:$PORT/sub"
echo "管理面板: http://$ARGO_ADDR:$PORT"
echo "本地订阅: http://localhost:$PORT/sub"
echo "本地面板: http://localhost:$PORT"
echo
echo "=== 节点信息 ==="
echo "VLESS: $VLESS_URI"
echo "VMESS: $VMESS_URI"
echo "Trojan: $TROJAN_URI"
echo
echo "订阅链接:"
echo "$SUB_B64"
echo
echo "节点信息已保存到 $HOME/.xray_nodes_info"
{
    echo "UUID: $UUID"
    echo "VLESS: $VLESS_URI"
    echo "VMESS: $VMESS_URI"
    echo "Trojan: $TROJAN_URI"
} > $HOME/.xray_nodes_info

echo "=== 重要提示 ==="
echo "部署已完成，节点信息已生成"
echo "可以立即使用订阅地址导入客户端"
echo "已集成 YouTube/Netflix/Disney/PrimeVideo 分流规则"
echo "服务将持续在后台运行"
echo
echo "部署完成！感谢使用！"
