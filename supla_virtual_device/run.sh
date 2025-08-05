#!/usr/bin/env bash
set -e

CONFIG_PATH="/data/options.json"
SHARED_DIR="/config/supla-virtual-device"

# Kolory dla logów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Zmienne globalne dla monitorowania
RESTART_COUNT=0
MAX_RESTARTS=10
LAST_SUCCESS_TIME=$(date +%s)
STARTUP_TIME=$(date +%s)
WATCHDOG_PID=""

# Funkcja logowania z timestamp
function log() {
    local level=$1
    local msg=$2
    case $level in
        "INFO")  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${BLUE}[INFO]${NC} ${msg}" ;;
        "WARN")  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}[WARN]${NC} ${msg}" ;;
        "ERROR") echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${RED}[ERROR]${NC} ${msg}" ;;
        "SUCCESS") echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${GREEN}[SUCCESS]${NC} ${msg}" ;;
        "CONFIG") echo -e "${PURPLE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${PURPLE}[CONFIG]${NC} ${msg}" ;;
        "BUILD") echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${CYAN}[BUILD]${NC} ${msg}" ;;
        "RESTART") echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}[RESTART]${NC} ${msg}" ;;
        "WATCHDOG") echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${CYAN}[WATCHDOG]${NC} ${msg}" ;;
    esac
}

log "INFO" "🚀 Starting SUPLA Virtual Device addon with cloud watchdog"
log "INFO" "📁 Using persistent storage: $SHARED_DIR"

# Funkcja do odczytywania opcji z Home Assistant
function get_option() {
    local key=$1
    local default_value=$2
    jq --raw-output --arg key "$key" --arg default "$default_value" \
        '.[$key] // $default' $CONFIG_PATH
}

# 🐕 UPROSZCZONA FUNKCJA - restart po pierwszym niepowodzeniu
function watchdog_loop() {
    local enabled=$(get_option "watchdog_enabled" "false")
    
    if [[ "$enabled" != "true" ]]; then
        log "WATCHDOG" "🐕 Watchdog disabled in configuration"
        return 0
    fi
    
    local code=$(get_option "watchdog_code" "")
    local url=$(get_option "watchdog_url" "")
    local interval=$(get_option "watchdog_interval" "60")
    
    # Walidacja intervalu (1-300 sekund)
    if (( interval < 1 )); then
        interval=1
        log "WARN" "🐕 Watchdog interval too small, using 1s"
    elif (( interval > 300 )); then
        interval=300
        log "WARN" "🐕 Watchdog interval too large, using 300s"
    fi
    
    if [[ -z "$code" || -z "$url" ]]; then
        log "WARN" "🐕 Watchdog enabled but code or URL not configured"
        return 1
    fi
    
    log "WATCHDOG" "🐕 Starting SUPLA Cloud Watchdog"
    log "WATCHDOG" "📡 URL: $url"
    log "WATCHDOG" "🔑 Code: ${code:0:8}..."
    log "WATCHDOG" "⏱️  Interval: ${interval}s (immediate restart on failure)"
    
    # Czekaj 30 sekund na startup
    sleep 30
    
    while true; do
        log "WATCHDOG" "🔍 Checking device status via SUPLA Cloud API"
        
        # Wykonaj zapytanie do SUPLA Cloud API
        local response=$(curl -s \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -X PATCH \
            -d "{\"code\":\"$code\",\"action\":\"read\"}" \
            "$url" 2>/dev/null)
        
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -ne 0 ]]; then
            log "ERROR" "🐕 ❌ API request failed (curl exit code: $curl_exit_code)"
            log "RESTART" "🐕 🔄 Triggering immediate restart due to API failure"
            
            # Natychmiastowy restart
            pkill -f supla-virtual-device 2>/dev/null || true
            sleep 10
            
        else
            # Parsuj JSON response
            local connected=$(echo "$response" | jq -r '.connected' 2>/dev/null)
            local connected_code=$(echo "$response" | jq -r '.connectedCode' 2>/dev/null)
            
            if [[ "$connected" == "true" ]]; then
                log "SUCCESS" "🐕 ✅ Device is CONNECTED ($connected_code)"
                LAST_SUCCESS_TIME=$(date +%s)
            elif [[ "$connected" == "false" ]]; then
                log "ERROR" "🐕 ❌ Device is DISCONNECTED ($connected_code)"
                log "RESTART" "🐕 🔄 Triggering immediate restart due to disconnection"
                
                # Natychmiastowy restart
                pkill -f supla-virtual-device 2>/dev/null || true
                sleep 10
                
            else
                log "WARN" "🐕 ⚠️  Invalid response from API: $response"
                log "RESTART" "🐕 🔄 Triggering immediate restart due to invalid response"
                
                # Natychmiastowy restart
                pkill -f supla-virtual-device 2>/dev/null || true
                sleep 10
            fi
        fi
        
        # Czekaj do następnego sprawdzenia
        sleep "$interval"
    done
}


# Funkcja sprawdzania zdrowia procesu
function check_process_health() {
    local pid=$1
    local timeout=300  # 5 minut timeout
    
    while true; do
        if ! kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "💀 Process died (PID: $pid)"
            return 1
        fi
        
        # Sprawdź czy proces nie zawisnął
        local current_time=$(date +%s)
        local idle_time=$((current_time - LAST_SUCCESS_TIME))
        
        if [[ $idle_time -gt $timeout ]]; then
            log "WARN" "⚠️  Process appears hung (idle for ${idle_time}s)"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
            kill -KILL "$pid" 2>/dev/null || true
            return 1
        fi
        
        sleep 60
        log "INFO" "💓 Health check OK (PID: $pid, idle: ${idle_time}s)"
    done
}

# ULEPSZONA funkcja konfiguracji
function ensure_persistent_config() {
    local config_file="$SHARED_DIR/supla-virtual-device.cfg"
    
    log "CONFIG" "🔧 Starting configuration management"
    
    local old_guid=""
    local old_authkey=""
    local channels_config=""
    
    if [[ -f "$config_file" ]]; then
        log "CONFIG" "📝 Found existing configuration, preserving keys and channels"
        
        old_guid=$(grep -E '^device_guid=' "$config_file" | cut -d= -f2-)
        old_authkey=$(grep -E '^auth_key=' "$config_file" | cut -d= -f2-)
        channels_config=$(awk '/^\[CHANNEL_/{flag=1} flag{print} /^$/{if(flag) flag=0}' "$config_file")
        
        log "CONFIG" "🔑 Preserved GUID: ${old_guid:0:8}..."
        log "CONFIG" "🔐 Preserved AuthKey: ${old_authkey:0:8}..."
    else
        log "CONFIG" "🆕 Creating new configuration"
    fi
    
    # Pobierz ustawienia z HA
    local device_name=$(get_option "device_name" "SUPLA VIRTUAL DEVICE")
    local server_host=$(get_option "server_host" "svrX.supla.org")
    local protocol_version=$(get_option "protocol_version" "12")
    local email=$(get_option "email" "")
    
    # Użyj zachowanych kluczy lub wygeneruj nowe
    local device_guid="$old_guid"
    if [[ -z "$device_guid" ]]; then
        device_guid=$(get_option "device_guid" "")
        if [[ -z "$device_guid" ]]; then
            device_guid=$(openssl rand -hex 16)
            log "CONFIG" "🎲 Generated new GUID: $device_guid"
        fi
    fi
    
    local auth_key="$old_authkey"
    if [[ -z "$auth_key" ]]; then
        auth_key=$(get_option "auth_key" "")
        if [[ -z "$auth_key" ]]; then
            auth_key=$(openssl rand -hex 16)
            log "CONFIG" "🔐 Generated new AuthKey: ${auth_key:0:8}..."
        fi
    fi
    
    local mqtt_enabled=$(get_option "mqtt_enabled" "false")
    local mqtt_host=$(get_option "mqtt_host" "")
    local mqtt_port=$(get_option "mqtt_port" "1883")
    local mqtt_username=$(get_option "mqtt_username" "")
    local mqtt_password=$(get_option "mqtt_password" "")
    local mqtt_client_name=$(get_option "mqtt_client_name" "supla-virtual-device")

    if [[ -z "$email" ]]; then
        log "ERROR" "❌ Email is required!"
        exit 1
    fi

    # Wygeneruj konfigurację
    cat > "$config_file" << EOF
[GLOBAL]
device_name=$device_name
device_guid=$device_guid

[SERVER]
host=$server_host
protocol_version=$protocol_version

[AUTH]
email=$email
auth_key=$auth_key

[LOCATION]
location_id=0
location_password=""

EOF

    if [[ "$mqtt_enabled" == "true" ]]; then
        local unique_client_name="${mqtt_client_name}"
        
        cat >> "$config_file" << EOF
[MQTT]
host=$mqtt_host
port=$mqtt_port
username=$mqtt_username
password=$mqtt_password
client_name=$unique_client_name
keep_alive_sec=30
clean_session=true

EOF
        log "SUCCESS" "✅ MQTT configured"
    fi

    # Dopisz zachowane kanały
    if [[ -n "$channels_config" ]]; then
        echo "" >> "$config_file"
        echo "$channels_config" >> "$config_file"
        log "SUCCESS" "✅ Restored channel configurations"
    else
        cat >> "$config_file" << EOF
# 
# KANAŁY - skonfiguruj ręcznie według dokumentacji GitHub:
# https://github.com/lukbek/supla-virtual-device
#

EOF
    fi

    log "SUCCESS" "✅ Configuration completed"
}

# Funkcja uruchamiania SUPLA z monitorowaniem
function run_supla_with_monitoring() {
    local attempt=$1
    
    log "INFO" "🎯 Starting SUPLA Virtual Device (attempt #$attempt)"
    
    ./supla-virtual-device 2>&1 | while IFS= read -r line; do
        LAST_SUCCESS_TIME=$(date +%s)
        
        # Enhanced logging z kolorowaniem
        if [[ "$line" == *"disconnect"* || "$line" == *"Disconnect"* ]]; then
            log "WARN" "🔌 DISCONNECTED: $line"
        elif [[ "$line" == *"connected"* || "$line" == *"Connected"* ]]; then
            log "SUCCESS" "✅ CONNECTED: $line"
            LAST_SUCCESS_TIME=$(date +%s)
        elif [[ "$line" == *"registered"* || "$line" == *"Registered"* ]]; then
            log "SUCCESS" "🎉 REGISTERED: $line"
            LAST_SUCCESS_TIME=$(date +%s)
        elif [[ "$line" == *"mqtt"* || "$line" == *"MQTT"* ]]; then
            if [[ "$line" == *"error"* ]]; then
                log "ERROR" "❌ MQTT ERROR: $line"
            else
                log "INFO" "📡 MQTT: $line"
            fi
        elif [[ "$line" == *"error"* || "$line" == *"ERROR"* ]]; then
            log "ERROR" "❌ ERROR: $line"
        else
            log "INFO" "ℹ️  $line"
        fi
    done &
    
    local supla_pid=$!
    log "INFO" "🎬 SUPLA started with PID: $supla_pid"
    
    # Uruchom monitoring w tle
    check_process_health $supla_pid &
    local monitor_pid=$!
    
    wait $supla_pid
    local exit_code=$?
    
    kill $monitor_pid 2>/dev/null || true
    log "WARN" "⚠️  SUPLA process exited with code: $exit_code"
    
    return $exit_code
}

# Główna funkcja z auto-restart i watchdog
function main() {
    # Setup
    mkdir -p "$SHARED_DIR"
    cd "$SHARED_DIR"
    log "INFO" "📂 Working directory: $(pwd)"
    
    ensure_persistent_config
    
    # Build lub użyj cache
    if [[ -f "supla-virtual-device" ]]; then
        log "SUCCESS" "✅ Using existing build"
    else
        log "BUILD" "🏗️  Building SUPLA Virtual Device..."
        
        if [ ! -d src ]; then
            git clone https://github.com/lukbek/supla-core.git -q --single-branch --branch supla-mqtt-dev src >/dev/null || exit 1
        fi
        
        (cd src && git pull >/dev/null && cd ..) || exit 1
        (cd src/supla-dev/Release && make all >/dev/null 2>&1 && cd ../../..) || exit 1
        
        if [ ! -f supla-virtual-device ]; then
            ln -s src/supla-dev/Release/supla-virtual-device supla-virtual-device
        fi
        
        log "SUCCESS" "🎉 Build completed"
    fi
    
    mkdir -p ./var
    chmod 777 ./var
    chmod +x ./supla-virtual-device
    
    # 🐕 URUCHOM WATCHDOG W TLE
    watchdog_loop &
    WATCHDOG_PID=$!
    log "INFO" "🐕 Cloud watchdog started with PID: $WATCHDOG_PID"
    
    # PĘTLA AUTO-RESTART
    log "INFO" "🔄 Starting auto-restart loop (max $MAX_RESTARTS restarts)"
    
    while [[ $RESTART_COUNT -lt $MAX_RESTARTS ]]; do
        local current_time=$(date +%s)
        local uptime=$((current_time - STARTUP_TIME))
        
        if [[ $uptime -gt 3600 ]]; then
            RESTART_COUNT=0
            STARTUP_TIME=$current_time
            log "INFO" "⏰ Uptime > 1h, resetting restart counter"
        fi
        
        if run_supla_with_monitoring $((RESTART_COUNT + 1)); then
            log "SUCCESS" "✅ SUPLA exited normally"
            break
        else
            RESTART_COUNT=$((RESTART_COUNT + 1))
            
            if [[ $RESTART_COUNT -lt $MAX_RESTARTS ]]; then
                local delay=$((RESTART_COUNT * 10))
                log "RESTART" "🔄 Restart #$RESTART_COUNT/$MAX_RESTARTS in ${delay}s"
                sleep $delay
            else
                log "ERROR" "💥 Max restarts reached ($MAX_RESTARTS)"
                exit 1
            fi
        fi
    done
    
    log "INFO" "🏁 Auto-restart loop ended"
}

# Obsługa sygnałów
cleanup() {
    log "WARN" "🛑 Received shutdown signal"
    log "INFO" "🧹 Cleaning up processes"
    
    # Zakończ watchdog
    if [[ -n "$WATCHDOG_PID" ]]; then
        kill $WATCHDOG_PID 2>/dev/null || true
        log "INFO" "🐕 Watchdog stopped"
    fi
    
    # Zakończ SUPLA
    pkill -f supla-virtual-device 2>/dev/null || true
    pkill -f check_process_health 2>/dev/null || true
    
    log "SUCCESS" "✅ Cleanup completed"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Uruchomienie
main
wait
