#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
WORK_DIR="/data"
CONFIG_FILE="${WORK_DIR}/supla-virtual-device.cfg"
ADDON_CONFIG_DIR="/config"
USER_CONFIG_FILE="${ADDON_CONFIG_DIR}/supla-virtual-device.cfg"
HOMEASSISTANT_CONFIG_DIR="/homeassistant"
STATE_DIR="${WORK_DIR}/var"
SAMPLE_FILE="/usr/local/share/supla-virtual-device.cfg.sample"
MQTT_CHECK_INTERVAL_SEC=5
MQTT_CONNECT_TIMEOUT_SEC=2

child_pid=""

log() {
    local level="$1"
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

legacy_config_from_options() {
    jq -r '.config // ""' "${OPTIONS_FILE}"
}

ensure_user_config_file() {
    local tmp_file legacy_config

    mkdir -p "${ADDON_CONFIG_DIR}"

    if [[ -f "${USER_CONFIG_FILE}" ]]; then
        return 0
    fi

    tmp_file="$(mktemp)"
    legacy_config="$(legacy_config_from_options)"

    if grep -q '[^[:space:]]' <<<"${legacy_config}"; then
        log INFO "Migrating legacy addon option 'config' to ${USER_CONFIG_FILE}"
        printf '%s\n' "${legacy_config}" > "${tmp_file}"
    else
        log WARN "Missing ${USER_CONFIG_FILE}, creating it from bundled sample configuration"
        cp "${SAMPLE_FILE}" "${tmp_file}"
    fi

    sed -i 's/\r$//' "${tmp_file}"
    mv "${tmp_file}" "${USER_CONFIG_FILE}"
}

write_runtime_config_from_file() {
    local tmp_file
    tmp_file="$(mktemp)"

    cp "${USER_CONFIG_FILE}" "${tmp_file}"
    sed -i 's/\r$//' "${tmp_file}"
    mv "${tmp_file}" "${CONFIG_FILE}"
}

prepare_runtime() {
    mkdir -p "${WORK_DIR}" "${STATE_DIR}" "${ADDON_CONFIG_DIR}"
    chmod 755 "${WORK_DIR}" "${STATE_DIR}" "${ADDON_CONFIG_DIR}"

    if [[ ! -f "${OPTIONS_FILE}" ]]; then
        log ERROR "Missing ${OPTIONS_FILE}"
        exit 1
    fi

    ensure_user_config_file
    write_runtime_config_from_file
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

get_config_value() {
    local section="$1"
    local key="$2"

    awk -F '=' -v section="${section}" -v key="${key}" '
        function trim(s) {
            sub(/^[ \t\r\n]+/, "", s)
            sub(/[ \t\r\n]+$/, "", s)
            return s
        }

        /^[[:space:]]*[#;]/ { next }

        /^[[:space:]]*\[/ {
            current = trim($0)
            in_section = (current == "[" section "]")
            next
        }

        !in_section { next }

        {
            pos = index($0, "=")
            if (pos == 0) next

            current_key = trim(substr($0, 1, pos - 1))
            current_value = trim(substr($0, pos + 1))

            if (current_key == key) {
                print current_value
                exit
            }
        }
    ' "${CONFIG_FILE}"
}

mqtt_host() {
    get_config_value "MQTT" "host"
}

mqtt_port() {
    local port
    port="$(get_config_value "MQTT" "port")"
    if [[ -z "${port}" ]]; then
        port="1883"
    fi
    printf '%s' "${port}"
}

is_mqtt_configured() {
    [[ -n "$(trim "$(mqtt_host)")" ]]
}

mqtt_available() {
    local host port
    host="$(trim "$(mqtt_host)")"
    port="$(trim "$(mqtt_port)")"

    if [[ -z "${host}" ]]; then
        return 0
    fi

    timeout "${MQTT_CONNECT_TIMEOUT_SEC}" bash -c "exec 3<>/dev/tcp/${host}/${port}" \
        >/dev/null 2>&1
}

wait_for_mqtt() {
    local host port
    host="$(trim "$(mqtt_host)")"
    port="$(trim "$(mqtt_port)")"

    if [[ -z "${host}" ]]; then
        return 0
    fi

    log INFO "MQTT watchdog enabled for ${host}:${port}"

    until mqtt_available; do
        log WARN "MQTT broker ${host}:${port} unavailable, waiting before starting SUPLA Virtual Device"
        sleep "${MQTT_CHECK_INTERVAL_SEC}"
    done
}

stop_child() {
    local pid="${child_pid}"

    if [[ -z "${pid}" ]]; then
        return 0
    fi

    if ! kill -0 "${pid}" >/dev/null 2>&1; then
        child_pid=""
        return 0
    fi

    kill "${pid}" >/dev/null 2>&1 || true

    for _ in 1 2 3 4 5; do
        if ! kill -0 "${pid}" >/dev/null 2>&1; then
            child_pid=""
            return 0
        fi
        sleep 1
    done

    kill -9 "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    child_pid=""
}

handle_exit() {
    stop_child
}

start_supla() {
    local -a args=("$@")

    /usr/local/bin/supla-virtual-device "${args[@]}" &
    child_pid="$!"
    log INFO "SUPLA Virtual Device started with PID ${child_pid}"
}

main() {
    local args=()

    prepare_runtime
    cd "${WORK_DIR}"
    trap handle_exit EXIT INT TERM

    if jq -e '.debug == true' "${OPTIONS_FILE}" > /dev/null 2>&1; then
        args+=("-D")
        log INFO "Debug logging enabled"
    fi

    log INFO "Using configuration from addon config file"
    log INFO "Addon config file: ${USER_CONFIG_FILE}"
    log INFO "Runtime config file: ${CONFIG_FILE}"
    log INFO "Persistent state directory: ${STATE_DIR}"
    log INFO "Home Assistant config directory inside container: ${HOMEASSISTANT_CONFIG_DIR}"
    if ! is_mqtt_configured; then
        log INFO "MQTT not configured, starting SUPLA Virtual Device without MQTT watchdog"
        exec /usr/local/bin/supla-virtual-device "${args[@]}"
    fi

    while true; do
        wait_for_mqtt
        log INFO "Starting SUPLA Virtual Device"
        start_supla "${args[@]}"

        while kill -0 "${child_pid}" >/dev/null 2>&1; do
            if ! mqtt_available; then
                log WARN "MQTT broker unavailable, stopping SUPLA Virtual Device until broker returns"
                stop_child
                break
            fi

            sleep "${MQTT_CHECK_INTERVAL_SEC}"
        done

        if [[ -n "${child_pid}" ]]; then
            wait "${child_pid}" >/dev/null 2>&1 || true
            child_pid=""
            log WARN "SUPLA Virtual Device exited, restarting when conditions are met"
            sleep "${MQTT_CHECK_INTERVAL_SEC}"
        fi
    done
}

main "$@"
