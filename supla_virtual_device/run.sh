#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
WORK_DIR="/data"
CONFIG_FILE="${WORK_DIR}/supla-virtual-device.cfg"
STATE_DIR="${WORK_DIR}/var"
SAMPLE_FILE="/usr/local/share/supla-virtual-device.cfg.sample"
MQTT_CHECK_INTERVAL_SEC=5
MQTT_MONITOR_START_GRACE_SEC=2

child_pid=""
mqtt_monitor_pid=""

log() {
    local level="$1"
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

write_config_from_options() {
    local tmp_file
    tmp_file="$(mktemp)"

    jq -r '.config // ""' "${OPTIONS_FILE}" > "${tmp_file}"

    if ! grep -q '[^[:space:]]' "${tmp_file}"; then
        log WARN "Addon option 'config' is empty, using bundled sample configuration"
        cp "${SAMPLE_FILE}" "${tmp_file}"
    fi

    sed -i 's/\r$//' "${tmp_file}"
    mv "${tmp_file}" "${CONFIG_FILE}"
}

prepare_runtime() {
    mkdir -p "${WORK_DIR}" "${STATE_DIR}"
    chmod 755 "${WORK_DIR}" "${STATE_DIR}"

    if [[ ! -f "${OPTIONS_FILE}" ]]; then
        log ERROR "Missing ${OPTIONS_FILE}"
        exit 1
    fi

    write_config_from_options
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

mqtt_username() {
    get_config_value "MQTT" "username"
}

mqtt_password() {
    get_config_value "MQTT" "password"
}

mqtt_client_name() {
    get_config_value "MQTT" "client_name"
}

mqtt_monitor_client_id() {
    local client_name
    client_name="$(trim "$(mqtt_client_name)")"

    if [[ -z "${client_name}" ]]; then
        client_name="supla-virtual-device"
    fi

    printf '%s-watchdog' "${client_name}"
}

is_mqtt_configured() {
    [[ -n "$(trim "$(mqtt_host)")" ]]
}

stop_mqtt_monitor() {
    local pid="${mqtt_monitor_pid}"

    if [[ -z "${pid}" ]]; then
        return 0
    fi

    if ! kill -0 "${pid}" >/dev/null 2>&1; then
        wait "${pid}" >/dev/null 2>&1 || true
        mqtt_monitor_pid=""
        return 0
    fi

    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    mqtt_monitor_pid=""
}

mqtt_monitor_running() {
    local pid="${mqtt_monitor_pid}"
    local stat=""

    if [[ -z "${pid}" ]]; then
        return 1
    fi

    if ! kill -0 "${pid}" >/dev/null 2>&1; then
        wait "${pid}" >/dev/null 2>&1 || true
        mqtt_monitor_pid=""
        return 1
    fi

    stat="$(ps -o stat= -p "${pid}" 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "${stat}" || "${stat}" == Z* ]]; then
        wait "${pid}" >/dev/null 2>&1 || true
        mqtt_monitor_pid=""
        return 1
    fi

    return 0
}

mqtt_monitor_connected() {
    mqtt_monitor_running || return 1
    ss -ntpH 2>/dev/null | grep -F "ESTAB" | grep -F "pid=${mqtt_monitor_pid}," >/dev/null 2>&1
}

start_mqtt_monitor() {
    local host port username password client_id
    local -a cmd

    host="$(trim "$(mqtt_host)")"
    port="$(trim "$(mqtt_port)")"
    username="$(trim "$(mqtt_username)")"
    password="$(trim "$(mqtt_password)")"
    client_id="$(mqtt_monitor_client_id)"

    if [[ -z "${host}" ]]; then
        return 0
    fi

    stop_mqtt_monitor

    cmd=(
        mosquitto_sub
        -h "${host}"
        -p "${port}"
        -i "${client_id}"
        -t '$SYS/broker/uptime'
        -q 0
        -R
    )

    if [[ -n "${username}" ]]; then
        cmd+=(-u "${username}")
    fi

    if [[ -n "${password}" ]]; then
        cmd+=(-P "${password}")
    fi

    "${cmd[@]}" >/dev/null 2>&1 &
    mqtt_monitor_pid="$!"

    sleep "${MQTT_MONITOR_START_GRACE_SEC}"

    mqtt_monitor_connected
}

wait_for_mqtt() {
    local host port
    host="$(trim "$(mqtt_host)")"
    port="$(trim "$(mqtt_port)")"

    if [[ -z "${host}" ]]; then
        return 0
    fi

    log INFO "MQTT watchdog enabled for ${host}:${port}"

    while true; do
        if start_mqtt_monitor; then
            return 0
        fi

        log WARN "MQTT broker ${host}:${port} unavailable, waiting before starting SUPLA Virtual Device"
        stop_mqtt_monitor
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
    stop_mqtt_monitor
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

    log INFO "Using configuration from Home Assistant addon options"
    log INFO "Config file: ${CONFIG_FILE}"
    log INFO "Persistent state directory: ${STATE_DIR}"
    if ! is_mqtt_configured; then
        log INFO "MQTT not configured, starting SUPLA Virtual Device without MQTT watchdog"
        exec /usr/local/bin/supla-virtual-device "${args[@]}"
    fi

    while true; do
        wait_for_mqtt
        log INFO "Starting SUPLA Virtual Device"
        start_supla "${args[@]}"

        while kill -0 "${child_pid}" >/dev/null 2>&1; do
            if ! mqtt_monitor_connected; then
                log WARN "MQTT broker unavailable, stopping SUPLA Virtual Device until broker returns"
                stop_child
                break
            fi

            sleep 1
        done

        stop_mqtt_monitor

        if [[ -n "${child_pid}" ]]; then
            wait "${child_pid}" >/dev/null 2>&1 || true
            child_pid=""
            log WARN "SUPLA Virtual Device exited, restarting when conditions are met"
            sleep "${MQTT_CHECK_INTERVAL_SEC}"
        fi
    done
}

main "$@"
