#!/usr/bin/env bash
set -e

CONFIG_PATH="/data/options.json"
SHARED_DIR="/config/supla-virtual-device"

# Kolory dla logów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[INFO]${NC} Starting SUPLA Virtual Device addon..."
echo -e "${BLUE}[INFO]${NC} Using persistent storage: $SHARED_DIR"

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
    
    local old_guid=""
    local old_authkey=""
    local channels_config=""
    
    # Sprawdź czy istnieje plik konfiguracyjny i wyciągnij z niego klucze/kanały
    if [[ -f "$config_file" ]]; then
        echo -e "${YELLOW}[CONFIG]${NC} Updating configuration with new HA settings, preserving keys and channels"
        
        # Wyciągnij istniejący device_guid i auth_key
        old_guid=$(grep -E '^device_guid=' "$config_file" | cut -d= -f2-)
        old_authkey=$(grep -E '^auth_key=' "$config_file" | cut -d= -f2-)
        
        # Wyciągnij wszystkie bloki kanałów [CHANNEL_X]
        channels_config=$(awk '/^\[CHANNEL_[0-9]+\]/{flag=1} flag{print} /^$/{if(flag) flag=0}' "$config_file")
        
        echo -e "${GREEN}[CONFIG]${NC} Preserved GUID: ${old_guid:0:8}..."
        echo -e "${GREEN}[CONFIG]${NC} Preserved AuthKey: ${old_authkey:0:8}..."
        if [[ -n "$channels_config" ]]; then
            local channel_count=$(echo "$channels_config" | grep -c '^\[CHANNEL_' || echo "0")
            echo -e "${GREEN}[CONFIG]${NC} Preserved $channel_count channel(s)"
        fi
    else
        echo -e "${YELLOW}[CONFIG]${NC} Creating new persistent configuration..."
    fi
    
    # Pobierz podstawowe ustawienia z HA
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
            echo -e "${YELLOW}[CONFIG]${NC} Generated new GUID: $device_guid"
        fi
    fi
    
    local auth_key="$old_authkey"
    if [[ -z "$auth_key" ]]; then
        auth_key=$(get_option "auth_key" "")
        if [[ -z "$auth_key" ]]; then
            auth_key=$(openssl rand -hex 16)
            echo -e "${YELLOW}[CONFIG]${NC} Generated new AuthKey: ${auth_key:0:8}..."
        fi
    fi
    
    local mqtt_enabled=$(get_option "mqtt_enabled" "false")
    local mqtt_host=$(get_option "mqtt_host" "")
    local mqtt_port=$(get_option "mqtt_port" "1883")
    local mqtt_username=$(get_option "mqtt_username" "")
    local mqtt_password=$(get_option "mqtt_password" "")
    local mqtt_client_name=$(get_option "mqtt_client_name" "supla-virtual-device")

    if [[ -z "$email" ]]; then
        echo -e "${RED}[ERROR]${NC} Email is required!"
        exit 1
    fi

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
        # Dodaj unikalny suffix do client_name (rozwiązuje problem reconnect)
        local unique_suffix=$(openssl rand -hex 3)
        local unique_client_name="${mqtt_client_name}-${unique_suffix}"
        
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
        echo -e "${GREEN}[MQTT]${NC} MQTT configured with unique client: $unique_client_name"
    fi

    # Dopisz zachowane konfiguracje kanałów na końcu
    if [[ -n "$channels_config" ]]; then
        echo "" >> "$config_file"  # Pusta linia przed kanałami
        echo "$channels_config" >> "$config_file"
        echo -e "${GREEN}[CONFIG]${NC} Restored preserved channel configurations"
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
    fi

    echo -e "${GREEN}[CONFIG]${NC} Configuration updated with new HA settings and preserved data"
}

# Główna funkcja - używa /config/
function main() {
    # Utwórz persistent workspace w /config/
    mkdir -p "$SHARED_DIR"
    cd "$SHARED_DIR"
    
    echo -e "${BLUE}[INFO]${NC} Using persistent workspace: $SHARED_DIR"
    
    # Utwórz persistent konfigurację (tylko jeśli nie istnieje)
    ensure_persistent_config
    
    # Sprawdź czy jest już zbudowane
    if [[ -f "supla-virtual-device" ]]; then
        echo -e "${GREEN}[INFO]${NC} Using existing build"
    else
        echo -e "${BLUE}[INFO]${NC} Building SUPLA Virtual Device (first time)..."
        
        echo "Getting the sources."
        
        if [ ! -d src ]; then
            git clone https://github.com/lukbek/supla-core.git -q --single-branch --branch supla-mqtt-dev src >/dev/null || exit 1
        fi
        
        (cd src && git pull >/dev/null && cd ..) || exit 1
        
        echo "Building. Be patient."
        
        (cd src/supla-dev/Release && make all >/dev/null 2>&1 && cd ../../..) || exit 1
        
        if [ ! -f supla-virtual-device ]; then
            ln -s src/supla-dev/Release/supla-virtual-device supla-virtual-device
        fi
        
        echo -e "${GREEN}OK!${NC}"
    fi
    
    echo -e "${BLUE}[INFO]${NC} Starting SUPLA Virtual Device..."
    
    # Utwórz katalog var z uprawnieniami
    mkdir -p ./var
    chmod 777 ./var
    
    # Pokaż konfigurację przed uruchomieniem
    echo -e "${GREEN}[LAUNCH]${NC} Using configuration file:"
    echo -e "${BLUE}[DEBUG]${NC} Configuration content:"
    cat ./supla-virtual-device.cfg
    echo -e "${BLUE}[DEBUG]${NC} End of configuration"
    
    chmod +x ./supla-virtual-device
    
    # Uruchom SUPLA Virtual Device
    echo -e "${GREEN}[LAUNCH]${NC} Executing: ./supla-virtual-device"
    ./supla-virtual-device 2>&1 | while IFS= read -r line; do
        echo -e "${GREEN}[SUPLA]${NC} $(date '+%H:%M:%S') $line"
    done
}

# Obsługa sygnałów
cleanup() {
    echo -e "${YELLOW}[INFO]${NC} Shutting down gracefully..."
    pkill -f supla-virtual-device 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Uruchomienie głównej funkcji
main

# Utrzymywanie kontenera przy życiu
wait
