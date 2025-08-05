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
    esac
}

log "INFO" "🚀 Starting SUPLA Virtual Device addon"
log "INFO" "📁 Using persistent storage: $SHARED_DIR"

# Funkcja do odczytywania opcji z Home Assistant
function get_option() {
    local key=$1
    local default_value=$2
    jq --raw-output --arg key "$key" --arg default "$default_value" \
        '.[$key] // $default' $CONFIG_PATH
}

# ULEPSZONA funkcja - aktualizuje config z HA ale zachowuje klucze i kanały
function ensure_persistent_config() {
    local config_file="$SHARED_DIR/supla-virtual-device.cfg"
    
    log "CONFIG" "🔧 Starting configuration management"
    
    local old_guid=""
    local old_authkey=""
    local channels_config=""
    
    # Sprawdź czy istnieje plik konfiguracyjny i wyciągnij z niego klucze/kanały
    if [[ -f "$config_file" ]]; then
        log "CONFIG" "📝 Found existing configuration file, preserving keys and channels"
        
        # Wyciągnij istniejący device_guid i auth_key
        old_guid=$(grep -E '^device_guid=' "$config_file" | cut -d= -f2-)
        old_authkey=$(grep -E '^auth_key=' "$config_file" | cut -d= -f2-)
        
        # Wyciągnij wszystkie bloki kanałów [CHANNEL_X]
        channels_config=$(awk '/^\[CHANNEL_/{flag=1} flag{print} /^$/{if(flag) flag=0}' "$config_file")
        
        log "CONFIG" "🔑 Preserved GUID: ${old_guid:0:8}... (device identity maintained)"
        log "CONFIG" "🔐 Preserved AuthKey: ${old_authkey:0:8}... (authentication maintained)"
        if [[ -n "$channels_config" ]]; then
            local channel_count=$(echo "$channels_config" | grep -c '^\[CHANNEL_' || echo "0")
            log "CONFIG" "📡 Preserved $channel_count channel configuration(s)"
        fi
    else
        log "CONFIG" "🆕 No existing configuration found, creating new setup"
    fi
    
    log "CONFIG" "📥 Reading Home Assistant addon options"
    
    # Pobierz podstawowe ustawienia z HA
    local device_name=$(get_option "device_name" "SUPLA VIRTUAL DEVICE")
    local server_host=$(get_option "server_host" "svrX.supla.org")
    local protocol_version=$(get_option "protocol_version" "12")
    local email=$(get_option "email" "")
    
    log "CONFIG" "📟 Device name: $device_name"
    log "CONFIG" "🌐 SUPLA server: $server_host"
    log "CONFIG" "📧 User email: ${email:0:3}***@${email##*@}"
    
    # Użyj zachowanych kluczy lub wygeneruj nowe
    local device_guid="$old_guid"
    if [[ -z "$device_guid" ]]; then
        device_guid=$(get_option "device_guid" "")
        if [[ -z "$device_guid" ]]; then
            device_guid=$(openssl rand -hex 16)
            log "CONFIG" "🎲 Generated new GUID: $device_guid (this device will appear as NEW in SUPLA)"
        else
            log "CONFIG" "🔧 Using GUID from HA config: ${device_guid:0:8}..."
        fi
    else
        log "CONFIG" "♻️  Using persistent GUID: ${device_guid:0:8}... (same device in SUPLA)"
    fi
    
    local auth_key="$old_authkey"
    if [[ -z "$auth_key" ]]; then
        auth_key=$(get_option "auth_key" "")
        if [[ -z "$auth_key" ]]; then
            auth_key=$(openssl rand -hex 16)
            log "CONFIG" "🔐 Generated new AuthKey: ${auth_key:0:8}..."
        else
            log "CONFIG" "🔧 Using AuthKey from HA config: ${auth_key:0:8}..."
        fi
    else
        log "CONFIG" "♻️  Using persistent AuthKey: ${auth_key:0:8}..."
    fi
    
    local mqtt_enabled=$(get_option "mqtt_enabled" "false")
    local mqtt_host=$(get_option "mqtt_host" "")
    local mqtt_port=$(get_option "mqtt_port" "1883")
    local mqtt_username=$(get_option "mqtt_username" "")
    local mqtt_password=$(get_option "mqtt_password" "")
    local mqtt_client_name=$(get_option "mqtt_client_name" "supla-virtual-device")

    if [[ -z "$email" ]]; then
        log "ERROR" "❌ Email is required for SUPLA authentication!"
        exit 1
    fi

    log "CONFIG" "📝 Writing configuration file to: $config_file"

    # Wygeneruj nowy plik konfiguracyjny z aktualnymi ustawieniami HA
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
        
        log "CONFIG" "🔗 MQTT enabled - configuring broker connection"
        log "CONFIG" "🖥️  MQTT host: $mqtt_host:$mqtt_port"
        log "CONFIG" "👤 MQTT client: $unique_client_name"
        
        cat >> "$config_file" << EOF
[MQTT]
host=$mqtt_host
port=$mqtt_port
username=$mqtt_username
password=$mqtt_password
client_name=$unique_client_name
keep_alive_sec=60
clean_session=true

EOF
        log "SUCCESS" "✅ MQTT configuration completed"
    else
        log "CONFIG" "🚫 MQTT disabled - device will work without MQTT sensors"
    fi

    # Dopisz zachowane konfiguracje kanałów na końcu
    if [[ -n "$channels_config" ]]; then
        echo "" >> "$config_file"  # Pusta linia przed kanałami
        echo "$channels_config" >> "$config_file"
        local channel_count=$(echo "$channels_config" | grep -c '^\[CHANNEL_' || echo "0")
        log "SUCCESS" "✅ Restored $channel_count preserved channel configurations"
    else
        # Dodaj komentarz o ręcznej konfiguracji kanałów
        cat >> "$config_file" << EOF
# 
# KANAŁY - skonfiguruj ręcznie poniżej według dokumentacji GitHub:
# https://github.com/lukbek/supla-virtual-device
#
# Przykład kanału TEMPERATURE z JSON:
# [CHANNEL_0]
# function=TEMPERATURE
# state_topic=zigbee2mqtt/sensor1
# payload_value=/temperature
# min_interval_sec=10
#
# Przykład kanału RAW VALUE:
# [CHANNEL_1] 
# function=TEMPERATURE
# state_topic=sensors/temp/kitchen
# min_interval_sec=10
#

EOF
        log "CONFIG" "📋 No channels found - add manually to config file for sensor data"
    fi

    log "SUCCESS" "✅ Configuration management completed successfully"
}

# Główna funkcja - używa /config/
function main() {
    log "INFO" "🏗️  Setting up persistent workspace"
    
    # Utwórz persistent workspace w /config/
    mkdir -p "$SHARED_DIR"
    cd "$SHARED_DIR"
    
    log "INFO" "📂 Working directory: $(pwd)"
    
    # Utwórz persistent konfigurację (tylko jeśli nie istnieje)
    ensure_persistent_config
    
    log "BUILD" "🔍 Checking for existing SUPLA Virtual Device build"
    
    # Sprawdź czy jest już zbudowane
    if [[ -f "supla-virtual-device" ]]; then
        log "SUCCESS" "✅ Found existing build - skipping compilation"
        log "INFO" "⚡ This saves ~5-10 minutes of build time"
    else
        log "BUILD" "🏗️  No existing build found - starting compilation process"
        log "BUILD" "⏱️  This will take 5-10 minutes on first run..."
        
        log "BUILD" "📥 Downloading SUPLA core sources from GitHub"
        
        if [ ! -d src ]; then
            log "BUILD" "🔄 Cloning supla-core repository (branch: supla-mqtt-dev)"
            git clone https://github.com/lukbek/supla-core.git -q --single-branch --branch supla-mqtt-dev src >/dev/null || exit 1
            log "SUCCESS" "✅ Repository cloned successfully"
        else
            log "BUILD" "🔄 Updating existing repository"
        fi
        
        (cd src && git pull >/dev/null && cd ..) || exit 1
        log "SUCCESS" "✅ Sources updated to latest version"
        
        log "BUILD" "⚙️  Compiling SUPLA Virtual Device binary"
        log "BUILD" "🔨 Running: make all (this may take several minutes)"
        
        (cd src/supla-dev/Release && make all >/dev/null 2>&1 && cd ../../..) || exit 1
        
        if [ ! -f supla-virtual-device ]; then
            log "BUILD" "🔗 Creating symlink to compiled binary"
            ln -s src/supla-dev/Release/supla-virtual-device supla-virtual-device
        fi
        
        log "SUCCESS" "🎉 Build completed successfully!"
        log "INFO" "💾 Binary cached for future runs"
    fi
    
    log "INFO" "🚀 Preparing to start SUPLA Virtual Device"
    
    # Utwórz katalog var z uprawnieniami
    mkdir -p ./var
    chmod 777 ./var
    log "INFO" "📁 Created runtime directory: ./var"
    
    # Pokaż konfigurację przed uruchomieniem
    log "CONFIG" "📋 Current configuration file contents:"
    echo -e "${CYAN}╭─────────────────────────────────────╮${NC}"
    cat ./supla-virtual-device.cfg | while IFS= read -r line; do
        echo -e "${CYAN}│${NC} $line"
    done
    echo -e "${CYAN}╰─────────────────────────────────────╯${NC}"
    
    chmod +x ./supla-virtual-device
    log "SUCCESS" "✅ Binary permissions set"
    
    log "INFO" "🎯 Starting SUPLA Virtual Device process"
    log "INFO" "📡 Device will connect to SUPLA Cloud and start processing"
    
    # Uruchom SUPLA Virtual Device
    ./supla-virtual-device 2>&1 | while IFS= read -r line; do
        # Kolorowanie różnych typów logów SUPLA
        case "$line" in
            *"SUPLA-VIRTUAL-DEVICE"*) 
                echo -e "${GREEN}[SUPLA]${NC} $(date '+%H:%M:%S') 🎯 $line" ;;
            *"connected"*|*"Connected"*) 
                echo -e "${GREEN}[SUPLA]${NC} $(date '+%H:%M:%S') ✅ $line" ;;
            *"error"*|*"ERROR"*|*"Error"*) 
                echo -e "${RED}[SUPLA]${NC} $(date '+%H:%M:%S') ❌ $line" ;;
            *"mqtt"*|*"MQTT"*) 
                echo -e "${CYAN}[SUPLA]${NC} $(date '+%H:%M:%S') 📡 $line" ;;
            *"channel"*|*"Channel"*|*"CHANNEL"*) 
                echo -e "${PURPLE}[SUPLA]${NC} $(date '+%H:%M:%S') 📊 $line" ;;
            *"Registered"*|*"registered"*) 
                echo -e "${GREEN}[SUPLA]${NC} $(date '+%H:%M:%S') 🎉 $line" ;;
            *) 
                echo -e "${GREEN}[SUPLA]${NC} $(date '+%H:%M:%S') ℹ️  $line" ;;
        esac
    done
}

# Obsługa sygnałów
cleanup() {
    log "WARN" "🛑 Received shutdown signal"
    log "INFO" "🧹 Cleaning up SUPLA Virtual Device processes"
    pkill -f supla-virtual-device 2>/dev/null || true
    log "SUCCESS" "✅ Shutdown completed gracefully"
    exit 0
}

trap cleanup SIGTERM SIGINT

log "INFO" "🎬 Launching main process"

# Uruchomienie głównej funkcji
main

# Utrzymywanie kontenera przy życiu
wait
