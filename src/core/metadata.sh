# shellcheck shell=bash
# 职责: 节点元数据安全读写

reset_meta_info() {
    ip=""
    port=""
    password=""
    sni=""
    insecure=""
    up_mbps=""
    down_mbps=""
}

read_meta_info() {
    local key value
    local meta_ip="" meta_port="" meta_password="" meta_sni="" meta_insecure=""
    local meta_up="" meta_down=""
    reset_meta_info
    [[ -f "${HY2_META_FILE}" && -r "${HY2_META_FILE}" ]] || return 1

    # 仅解析白名单字段，不执行内容；兼容末行没有换行的旧元数据。
    while IFS='=' read -r key value || [[ -n "${key}" ]]; do
        case "${key}" in
            ip) meta_ip="${value}" ;;
            port) meta_port="${value}" ;;
            password) meta_password="${value}" ;;
            sni) meta_sni="${value}" ;;
            insecure) meta_insecure="${value}" ;;
            up_mbps) meta_up="${value}" ;;
            down_mbps) meta_down="${value}" ;;
        esac
    done < "${HY2_META_FILE}"

    if [[ -z "${meta_ip}" || -z "${meta_port}" || -z "${meta_password}" || -z "${meta_sni}" ]]; then
        return 1
    fi
    if ! is_valid_port "${meta_port}"; then
        return 1
    fi
    if [[ "${meta_insecure}" != "true" && "${meta_insecure}" != "false" ]]; then
        return 1
    fi
    [[ -z "${meta_up}" ]] && meta_up="${DEFAULT_UP_MBPS}"
    [[ -z "${meta_down}" ]] && meta_down="${DEFAULT_DOWN_MBPS}"
    if ! is_positive_integer "${meta_up}" || ! is_positive_integer "${meta_down}"; then
        return 1
    fi
    # 完整校验后才发布兼容字段；失败时不留下上一节点或半解析的数据。
    ip="${meta_ip}"
    port="$((10#${meta_port}))"
    password="${meta_password}"
    sni="${meta_sni}"
    insecure="${meta_insecure}"
    up_mbps="$((10#${meta_up}))"
    down_mbps="$((10#${meta_down}))"
    return 0
}

require_meta_info() {
    reset_meta_info
    if [[ ! -f "${HY2_META_FILE}" ]]; then
        err "未找到节点元数据，请先执行 (1) 配置 Hysteria2 节点！"
        sleep 2
        return 1
    fi
    if ! read_meta_info; then
        err "节点元数据损坏或缺失，请重新执行 (1) 配置节点。"
        sleep 2
        return 1
    fi
    return 0
}

write_meta_info() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local sni="$4"
    local insecure="$5"
    local up_mbps="$6"
    local down_mbps="$7"

    write_file_atomic "${HY2_META_FILE}" << EOF
ip=${ip}
port=${port}
password=${password}
sni=${sni}
insecure=${insecure}
up_mbps=${up_mbps}
down_mbps=${down_mbps}
EOF
}
