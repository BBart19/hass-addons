#!/usr/bin/env bash
set -euo pipefail

OPTIONS_FILE="/data/options.json"
WORK_DIR="/data"
CONFIG_FILE="${WORK_DIR}/supla-virtual-device.cfg"
STATE_DIR="${WORK_DIR}/var"
SAMPLE_FILE="/usr/local/share/supla-virtual-device.cfg.sample"

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

main() {
    local args=()

    prepare_runtime
    cd "${WORK_DIR}"

    if jq -e '.debug == true' "${OPTIONS_FILE}" > /dev/null 2>&1; then
        args+=("-D")
        log INFO "Debug logging enabled"
    fi

    log INFO "Using configuration from Home Assistant addon options"
    log INFO "Config file: ${CONFIG_FILE}"
    log INFO "Persistent state directory: ${STATE_DIR}"
    log INFO "Starting SUPLA Virtual Device"

    exec /usr/local/bin/supla-virtual-device "${args[@]}"
}

main "$@"
