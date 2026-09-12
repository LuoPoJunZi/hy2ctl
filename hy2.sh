#!/bin/bash
# 此文件同时作为生成版 hy2.sh 的开头；业务代码请修改 src/ 下对应模块。
# ==========================================
# 项目: hy2ctl 核心管理面板
# 描述: 专为恶劣网络环境打造的极简 Hysteria2 运维脚本
# ==========================================

# 交互式主面板不启用全局 errexit，各外部命令在对应流程中显式处理失败与回滚。

# --- 1. 全局变量与颜色输出 ---
sh_ver="v26.9.9"

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_blue="\033[0;36m"
_plain="\033[0m"

HY2_CONF_DIR="/etc/hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_SERVICE="hysteria-server.service"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
HY2_DIAG_DIR="/tmp"
HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
PANEL_UPDATE_URL="https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/hy2.sh"
PANEL_TARGET_BIN="/usr/local/bin/hy2"
PANEL_BACKUP_PREFIX="/usr/local/bin/hy2.bak"
HY2_INSTALL_URL="https://get.hy2.sh/"
HY2_SECURITY_BASELINE_VERSION="2.9.2"
RECOMMENDED_HY2_VERSION="2.12.2"
DEFAULT_PORT=8443
DEFAULT_MASQUERADE_URL="https://bing.com"
DEFAULT_SELF_SNI="bing.com"
DEFAULT_UP_MBPS=50
DEFAULT_DOWN_MBPS=200
DEFAULT_CERT_TYPE=2
SELF_SNI_PRESETS=("bing.com" "www.cloudflare.com" "www.apple.com" "www.microsoft.com" "www.amazon.com")
RUNTIME_FILE_NAMES=("config.yaml" "meta.info" "server.crt" "server.key")

# shellcheck shell=bash
# 职责: 终端消息与基础界面输出

msg() { printf '%b[信息]%b %s\n' "${_blue}" "${_plain}" "$1"; }

ok() { printf '%b[成功]%b %s\n' "${_green}" "${_plain}" "$1"; }

err() { printf '%b[错误]%b %s\n' "${_red}" "${_plain}" "$1"; }

print_line() { echo -e "${_blue}=====================================================${_plain}"; }

print_sub_line() { echo -e "${_blue}-----------------------------------------------------${_plain}"; }

wait_return() { read -n 1 -s -r -p "按任意键返回主菜单..."; }

# shellcheck shell=bash
# 职责: 交互输入边界；空行允许采用默认值，EOF 必须中止当前操作

read_input() {
    if ! read -r -p "$1" "$2"; then
        err "输入已结束，取消当前操作。" >&2
        return 1
    fi
}

# shellcheck shell=bash
# 职责: 运行环境、依赖和版本判断

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "请使用 root 用户运行此脚本。"
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "缺少依赖命令: ${cmd}"
        return 1
    fi
    return 0
}

preflight_check() {
    local missing=0
    local cmd
    local -a required_commands=(
        awk bash cat chmod chown clear cp curl date grep head hostname id journalctl
        ls mkdir mktemp mv openssl rm sed sleep systemctl tr
    )
    for cmd in "${required_commands[@]}"; do
        if ! require_cmd "${cmd}"; then
            missing=1
        fi
    done
    if [[ "${missing}" -ne 0 ]]; then
        err "运行环境依赖不完整，请先安装缺失命令后重试。"
        exit 1
    fi
    if ! systemctl list-unit-files >/dev/null 2>&1; then
        err "当前系统未检测到可用的 systemd 环境，脚本无法继续运行。"
        exit 1
    fi
}

ensure_hy2_core_installed() {
    if ! command -v hysteria >/dev/null 2>&1; then
        err "未检测到 Hysteria2 内核，请通过菜单 (11) 安装，或重新运行一键安装脚本。"
        return 1
    fi
    return 0
}

get_hy2_core_version() {
    local version_output
    command -v hysteria >/dev/null 2>&1 || return 1
    version_output="$(hysteria version 2>/dev/null)" || return 1
    [[ "${version_output}" =~ v[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[0]}"
}

version_at_least() {
    local current="${1#v}"
    local minimum="${2#v}"
    local current_major current_minor current_patch
    local minimum_major minimum_minor minimum_patch

    [[ "${current}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ "${minimum}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

    IFS=. read -r current_major current_minor current_patch <<< "${current}"
    IFS=. read -r minimum_major minimum_minor minimum_patch <<< "${minimum}"

    (( 10#${current_major} > 10#${minimum_major} )) && return 0
    (( 10#${current_major} < 10#${minimum_major} )) && return 1
    (( 10#${current_minor} > 10#${minimum_minor} )) && return 0
    (( 10#${current_minor} < 10#${minimum_minor} )) && return 1
    (( 10#${current_patch} >= 10#${minimum_patch} ))
}

# shellcheck shell=bash
# 职责: 用户输入格式校验

is_valid_port() {
    local p="$1"
    [[ "${p}" =~ ^[0-9]{1,5}$ ]] && (( 10#${p} >= 1 && 10#${p} <= 65535 ))
}

is_positive_integer() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]{1,9}$ ]] && (( 10#${value} >= 1 ))
}

is_valid_domain() {
    local d="$1"
    [[ "${d}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

is_valid_url() {
    local u="$1"
    [[ "${u}" =~ ^https?://[^[:space:]]+$ ]]
}

is_valid_email() {
    local e="$1"
    [[ "${e}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

# shellcheck shell=bash
# 职责: YAML、URL、JSON 与主机地址编码

yaml_single_quote() {
    local raw="$1"
    local escaped="${raw//\'/\'\'}"
    printf "'%s'" "${escaped}"
}

url_encode() {
    local raw="$1"
    local LC_ALL=C
    local length="${#raw}"
    local i char out=""
    for (( i = 0; i < length; i++ )); do
        char="${raw:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) out+="${char}" ;;
            *) printf -v out '%s%%%02X' "${out}" "'${char}" ;;
        esac
    done
    printf '%s' "${out}"
}

json_escape() {
    local s="$1"
    local code char escaped
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    # 常见字符串保留快速路径；其余 U+0001..U+001F 也必须转义为合法 JSON。
    # Bash 字符串无法保存 NUL，因此不接受/不宣称支持 U+0000 输入。
    if [[ "${s}" == *[$'\001'-$'\037']* ]]; then
        for ((code = 1; code < 32; code++)); do
            printf -v escaped '\\u%04x' "${code}"
            printf -v char '%b' "${escaped}"
            s="${s//"${char}"/"${escaped}"}"
        done
    fi
    printf '%s' "${s}"
}

format_host_for_url() {
    local host="$1"
    if [[ "${host}" == *:* ]]; then
        printf '[%s]' "${host}"
        return
    fi
    printf '%s' "${host}"
}

# shellcheck shell=bash
# 职责: 通用文件原子写入

write_file_atomic() {
    local target="$1"
    local tmp_file
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")" || return 1
    if ! cat > "${tmp_file}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    if ! mv -f "${tmp_file}" "${target}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}

# shellcheck shell=bash
# 职责: 有界脚本下载与服务器公网地址发现

# target 由调用方通过 mktemp 创建；失败后的删除、校验与替换仍由调用方负责。
download_script() {
    curl -fL --retry 2 --connect-timeout 8 --max-time 120 \
        -o "$2" "$1" >/dev/null 2>&1
}

fetch_server_ip() {
    local ip
    ip="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "${ip}" ]]; then
        ip="$(curl -fsS6 --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi
    echo "${ip}"
}

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

# shellcheck shell=bash
# 职责: 证书生成与校验值计算

normalize_certificate_sha256() {
    local fingerprint="$1"
    fingerprint="${fingerprint#*=}"
    fingerprint="${fingerprint//:/}"
    fingerprint="${fingerprint//[[:space:]]/}"
    fingerprint="${fingerprint,,}"
    [[ "${fingerprint}" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "${fingerprint}"
}

get_certificate_sha256() {
    local cert_file="$1"
    local fingerprint
    [[ -f "${cert_file}" ]] || return 1
    fingerprint="$(openssl x509 -in "${cert_file}" -noout -fingerprint -sha256 2>/dev/null)" || return 1
    normalize_certificate_sha256 "${fingerprint}"
}

is_valid_certificate_public_key_sha256() {
    local fingerprint="$1"
    [[ "${fingerprint}" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

get_certificate_public_key_sha256() {
    local cert_file="$1"
    local fingerprint
    [[ -f "${cert_file}" ]] || return 1
    fingerprint="$(
        set -o pipefail
        openssl x509 -in "${cert_file}" -pubkey -noout 2>/dev/null |
            openssl pkey -pubin -outform der 2>/dev/null |
            openssl dgst -sha256 -binary 2>/dev/null |
            openssl enc -base64 -A 2>/dev/null
    )" || return 1
    is_valid_certificate_public_key_sha256 "${fingerprint}" || return 1
    printf '%s' "${fingerprint}"
}

generate_self_signed_certificate() {
    local sni="$1"
    local cert_file="${HY2_CONF_DIR}/server.crt"
    local key_file="${HY2_CONF_DIR}/server.key"

    if openssl req -x509 -nodes -newkey ec \
        -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "${key_file}" -out "${cert_file}" \
        -subj "/CN=${sni}" -days 36500 \
        -addext "subjectAltName=DNS:${sni}" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1; then
        return 0
    fi

    openssl req -x509 -nodes -newkey ec \
        -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "${key_file}" -out "${cert_file}" \
        -subj "/CN=${sni}" -days 36500 >/dev/null 2>&1
}

# shellcheck shell=bash
# 职责: 配置、证书与 systemd 用户权限

set_config_dir_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown root:"${run_group}" "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
        chmod 750 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    else
        chmod 755 "${HY2_CONF_DIR}" >/dev/null 2>&1 || true
    fi
}

set_server_config_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown root:"${run_group}" "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
        chmod 640 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    else
        chmod 644 "${HY2_CONF_FILE}" >/dev/null 2>&1 || true
    fi
}

get_service_run_user() {
    local run_user
    run_user="$(systemctl show -p User --value "${HY2_SERVICE}" 2>/dev/null || true)"
    [[ -z "${run_user}" ]] && run_user="root"
    echo "${run_user}"
}

get_service_run_group() {
    local run_user="$1"
    local run_group
    run_group="$(systemctl show -p Group --value "${HY2_SERVICE}" 2>/dev/null || true)"
    if [[ -z "${run_group}" ]]; then
        run_group="$(id -gn "${run_user}" 2>/dev/null || true)"
    fi
    [[ -z "${run_group}" ]] && run_group="root"
    echo "${run_group}"
}

set_tls_file_permissions() {
    local run_user run_group
    run_user="$(get_service_run_user)"
    if [[ "${run_user}" != "root" ]] && id "${run_user}" >/dev/null 2>&1; then
        run_group="$(get_service_run_group "${run_user}")"
        chown "${run_user}:${run_group}" "${HY2_CONF_DIR}/server.key" "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
    fi
    chmod 600 "${HY2_CONF_DIR}/server.key" >/dev/null 2>&1 || true
    chmod 644 "${HY2_CONF_DIR}/server.crt" >/dev/null 2>&1 || true
}

# shellcheck shell=bash
# 职责: Hysteria2 四文件自动快照、缺失状态与恢复后的权限收敛

backup_runtime_files() {
    local name source_file backup_file absent_marker

    mkdir -p "${HY2_BACKUP_DIR}" || return 1

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        rm -f -- "${backup_file}" "${absent_marker}" || return 1
    done

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        source_file="${HY2_CONF_DIR}/${name}"
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        if [[ -e "${source_file}" ]]; then
            cp -p -- "${source_file}" "${backup_file}" || return 1
        else
            : > "${absent_marker}" || return 1
        fi
    done
    return 0
}

restore_runtime_files() {
    local name target_file backup_file absent_marker
    local restore_failed=0

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        target_file="${HY2_CONF_DIR}/${name}"
        backup_file="${HY2_BACKUP_DIR}/${name}.bak"
        absent_marker="${backup_file}.absent"
        if [[ -f "${backup_file}" ]]; then
            cp -p -- "${backup_file}" "${target_file}" || restore_failed=1
        elif [[ -f "${absent_marker}" ]]; then
            rm -f -- "${target_file}" || restore_failed=1
        else
            restore_failed=1
        fi
    done

    if [[ "${restore_failed}" -ne 0 ]]; then
        return 1
    fi

    set_config_dir_permissions
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        set_server_config_permissions
    fi
    if [[ -f "${HY2_META_FILE}" ]]; then
        chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true
    fi
    if [[ -f "${HY2_CONF_DIR}/server.key" && -f "${HY2_CONF_DIR}/server.crt" ]]; then
        set_tls_file_permissions
    fi
    return 0
}

# shellcheck shell=bash
# 职责: 配置失败回滚与启动故障提示

abort_pending_config_change() {
    local reason="$1"
    if restore_runtime_files; then
        err "${reason}，已恢复变更前文件。"
    else
        err "${reason}，且自动恢复失败，请立即检查 ${HY2_CONF_DIR}。"
    fi
}

restart_service_with_rollback() {
    if systemctl restart "${HY2_SERVICE}"; then
        return 0
    fi
    err "重启服务失败，正在尝试自动回滚到上一版配置..."
    show_service_failure_hint
    if restore_runtime_files && systemctl restart "${HY2_SERVICE}"; then
        err "已回滚到上一版配置，本次变更未生效。"
    else
        err "自动回滚失败，请手动检查 ${HY2_CONF_FILE} 和服务日志。"
    fi
    return 1
}

show_recent_service_logs() {
    print_line
    echo -e "${_yellow}[提示]${_plain} 最近 20 行服务日志："
    journalctl -u "${HY2_SERVICE}" --no-pager -n 20 2>/dev/null || true
    print_line
}

show_service_failure_hint() {
    local logs
    logs="$(journalctl -u "${HY2_SERVICE}" --no-pager -n 60 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [[ -z "${logs}" ]] && return 0

    if [[ "${logs}" == *"permission denied"* && "${logs}" == *"config.yaml"* ]]; then
        err "诊断结论：服务用户无权读取 config.yaml。"
        echo -e "      建议执行：systemctl show -p User,Group ${HY2_SERVICE}"
        echo -e "      建议执行：namei -l ${HY2_CONF_FILE}"
        return 0
    fi
    if [[ "${logs}" == *"address already in use"* || "${logs}" == *"bind: address already in use"* ]]; then
        err "诊断结论：监听端口被占用。"
        echo -e "      建议执行：ss -lntp | grep \":${port:-443}\\b\""
        return 0
    fi
    if [[ "${logs}" == *"acme"* && ( "${logs}" == *"timeout"* || "${logs}" == *"no such host"* || "${logs}" == *"dns"* ) ]]; then
        err "诊断结论：CA 证书申请失败（可能是 DNS/80/443 不通）。"
        echo -e "      建议检查：域名 A/AAAA 解析、80/443 入站、防火墙与云安全组。"
        return 0
    fi
    if [[ "${logs}" == *"failed to read server config"* || "${logs}" == *"yaml"* || "${logs}" == *"parse"* ]]; then
        err "诊断结论：配置文件内容异常或格式错误。"
        echo -e "      建议执行：hysteria server -c ${HY2_CONF_FILE}"
        return 0
    fi
}

# shellcheck shell=bash
# 职责: Hysteria2 服务状态变更；菜单交互位于 panel/service_menu.sh

change_hy2_service_state() {
    local action="$1"
    case "${action}" in
        start|stop|restart) systemctl "${action}" "${HY2_SERVICE}" ;;
        *) err "不支持的服务操作: ${action}"; return 1 ;;
    esac
}

# shellcheck shell=bash
# 职责: Hysteria2 内核安装、更新与卸载

verify_hy2_installer() {
    local file="$1"
    [[ -s "${file}" ]] || return 1
    head -n 1 "${file}" | grep -Eq '^#!(/bin/bash|/usr/bin/env bash)$' || return 1
    bash -n "${file}" >/dev/null 2>&1
}

install_hy2_core() {
    local installer_file installed_version

    if command -v hysteria &> /dev/null; then
        msg "Hysteria2 内核已安装，正在尝试更新..."
    else
        msg "正在调用官方脚本安装 Hysteria2 内核..."
    fi

    installer_file="$(mktemp /tmp/hysteria-install.XXXXXX)" || {
        err "创建内核安装临时文件失败。"
        return 1
    }

    if ! download_script "${HY2_INSTALL_URL}" "${installer_file}"; then
        rm -f -- "${installer_file}"
        err "下载安装脚本失败，请检查网络后重试。"
        return 1
    fi

    if ! verify_hy2_installer "${installer_file}"; then
        rm -f -- "${installer_file}"
        err "官方安装脚本内容无效，已停止执行。"
        return 1
    fi

    if ! bash "${installer_file}"; then
        rm -f -- "${installer_file}"
        err "内核安装/更新失败，请检查网络后重试。"
        return 1
    fi
    rm -f -- "${installer_file}"

    if ! systemctl enable "${HY2_SERVICE}" >/dev/null 2>&1; then
        err "已安装内核，但设置开机自启失败，请手动执行: systemctl enable ${HY2_SERVICE}"
        return 1
    fi
    installed_version="$(get_hy2_core_version 2>/dev/null || true)"
    if [[ -n "${installed_version}" ]]; then
        ok "Hysteria2 内核部署/更新完成，当前版本: ${installed_version}"
    else
        ok "Hysteria2 内核部署/更新完成！"
        msg "暂时无法读取内核版本，可返回主菜单再次查看。"
    fi
}

uninstall_hy2() {
    local confirm
    print_line
    echo -e "${_red}[警告] 这将彻底卸载 Hysteria2 及所有节点配置！${_plain}"
    read_input " => 确定要继续吗？(y/n): " confirm || return 1
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop "${HY2_SERVICE}" >/dev/null 2>&1 || true
        systemctl disable "${HY2_SERVICE}" >/dev/null 2>&1 || true

        rm -f /usr/local/bin/hysteria
        rm -rf /etc/hysteria
        rm -f /etc/systemd/system/hysteria-server.service
        systemctl daemon-reload
        ok "Hysteria2 已彻底卸载！"

        rm -f /usr/local/bin/hy2
        exit 0
    else
        msg "已取消卸载。"
    fi
}

# shellcheck shell=bash
# 职责: Hysteria2 服务端配置文件写入

write_ca_config() {
    local port="$1"
    local domain="$2"
    local email="$3"
    local password="$4"
    local masquerade_url="$5"

    write_file_atomic "${HY2_CONF_FILE}" << EOF
listen: :${port}
acme:
  domains:
    - $(yaml_single_quote "${domain}")
  email: $(yaml_single_quote "${email}")
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}

write_self_signed_config() {
    local port="$1"
    local password="$2"
    local masquerade_url="$3"

    write_file_atomic "${HY2_CONF_FILE}" << EOF
listen: :${port}
tls:
  cert: ${HY2_CONF_DIR}/server.crt
  key: ${HY2_CONF_DIR}/server.key
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}

# shellcheck shell=bash
# 职责: Hysteria2 节点配置输入收集与校验

reset_hy2_config_draft() {
    HY2_DRAFT_PORT=""
    HY2_DRAFT_PASSWORD=""
    HY2_DRAFT_MASQUERADE_URL=""
    HY2_DRAFT_UP_MBPS=""
    HY2_DRAFT_DOWN_MBPS=""
    HY2_DRAFT_CERT_TYPE=""
    HY2_DRAFT_DOMAIN=""
    HY2_DRAFT_EMAIL=""
    HY2_DRAFT_SNI=""
    HY2_DRAFT_INSECURE=""
}

collect_hy2_connection_settings() {
    local default_pwd

    read_input " => 请设置监听端口 (默认 ${DEFAULT_PORT}): " HY2_DRAFT_PORT || return 1
    [[ -z "${HY2_DRAFT_PORT}" ]] && HY2_DRAFT_PORT="${DEFAULT_PORT}"
    if ! is_valid_port "${HY2_DRAFT_PORT}"; then
        err "端口无效，请输入 1-65535 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_PORT="$((10#${HY2_DRAFT_PORT}))"

    if ! default_pwd="$(openssl rand -hex 16)" || [[ -z "${default_pwd}" ]]; then
        err "生成随机认证密码失败，请检查 openssl。"
        sleep 2
        return 1
    fi
    read_input " => 请设置认证密码 (默认随机: ${default_pwd}): " HY2_DRAFT_PASSWORD || return 1
    [[ -z "${HY2_DRAFT_PASSWORD}" ]] && HY2_DRAFT_PASSWORD="${default_pwd}"

    read_input " => 请设置伪装网址 (默认 ${DEFAULT_MASQUERADE_URL}): " HY2_DRAFT_MASQUERADE_URL || return 1
    [[ -z "${HY2_DRAFT_MASQUERADE_URL}" ]] && HY2_DRAFT_MASQUERADE_URL="${DEFAULT_MASQUERADE_URL}"
    if ! is_valid_url "${HY2_DRAFT_MASQUERADE_URL}"; then
        err "伪装网址格式无效，必须以 http:// 或 https:// 开头。"
        sleep 2
        return 1
    fi

    read_input " => 请设置上行带宽 Mbps (默认 ${DEFAULT_UP_MBPS}): " HY2_DRAFT_UP_MBPS || return 1
    [[ -z "${HY2_DRAFT_UP_MBPS}" ]] && HY2_DRAFT_UP_MBPS="${DEFAULT_UP_MBPS}"
    if ! is_positive_integer "${HY2_DRAFT_UP_MBPS}"; then
        err "上行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_UP_MBPS="$((10#${HY2_DRAFT_UP_MBPS}))"

    read_input " => 请设置下行带宽 Mbps (默认 ${DEFAULT_DOWN_MBPS}): " HY2_DRAFT_DOWN_MBPS || return 1
    [[ -z "${HY2_DRAFT_DOWN_MBPS}" ]] && HY2_DRAFT_DOWN_MBPS="${DEFAULT_DOWN_MBPS}"
    if ! is_positive_integer "${HY2_DRAFT_DOWN_MBPS}"; then
        err "下行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_DOWN_MBPS="$((10#${HY2_DRAFT_DOWN_MBPS}))"
}

pick_self_signed_sni() {
    local pick custom_sni
    PICKED_SNI=""
    echo -e " [*] 请选择自签 SNI 预设域名："
    echo -e "     (1) ${SELF_SNI_PRESETS[0]} (默认)"
    echo -e "     (2) ${SELF_SNI_PRESETS[1]}"
    echo -e "     (3) ${SELF_SNI_PRESETS[2]}"
    echo -e "     (4) ${SELF_SNI_PRESETS[3]}"
    echo -e "     (5) ${SELF_SNI_PRESETS[4]}"
    echo -e "     (0) 手动输入域名"
    read_input " [*] 请选择 [0-5] (默认 1): " pick || return 1
    [[ -z "${pick}" ]] && pick=1

    case "${pick}" in
        1) PICKED_SNI="${SELF_SNI_PRESETS[0]}" ;;
        2) PICKED_SNI="${SELF_SNI_PRESETS[1]}" ;;
        3) PICKED_SNI="${SELF_SNI_PRESETS[2]}" ;;
        4) PICKED_SNI="${SELF_SNI_PRESETS[3]}" ;;
        5) PICKED_SNI="${SELF_SNI_PRESETS[4]}" ;;
        0)
            read_input " [*] 请输入用于伪装的 SNI 域名 (默认 ${DEFAULT_SELF_SNI}): " custom_sni || return 1
            [[ -z "${custom_sni}" ]] && custom_sni="${DEFAULT_SELF_SNI}"
            PICKED_SNI="${custom_sni}"
            ;;
        *)
            err "输入无效，已使用默认 SNI: ${DEFAULT_SELF_SNI}"
            PICKED_SNI="${DEFAULT_SELF_SNI}"
            ;;
    esac
}

collect_hy2_certificate_settings() {
    echo -e "\n[*] 请选择证书模式："
    echo -e "  (1) CA 域名证书 (推荐，需要提前将域名解析到本 VPS)"
    echo -e "  (2) 自签证书 (默认，无需域名，直接使用 IP 连通)"
    read_input " => 请选择 [1-2] (默认 ${DEFAULT_CERT_TYPE}): " HY2_DRAFT_CERT_TYPE || return 1
    [[ -z "${HY2_DRAFT_CERT_TYPE}" ]] && HY2_DRAFT_CERT_TYPE="${DEFAULT_CERT_TYPE}"
    if [[ "${HY2_DRAFT_CERT_TYPE}" != "1" && "${HY2_DRAFT_CERT_TYPE}" != "2" ]]; then
        err "证书模式输入无效，请输入 1 或 2。"
        sleep 2
        return 1
    fi

    if [[ "${HY2_DRAFT_CERT_TYPE}" == "1" ]]; then
        read_input " [*] 请输入已解析到本机的域名: " HY2_DRAFT_DOMAIN || return 1
        if ! is_valid_domain "${HY2_DRAFT_DOMAIN}"; then
            err "域名格式无效，请输入有效域名（例如 example.com）。"
            sleep 2
            return 1
        fi
        read_input " [*] 请输入邮箱 (用于自动申请证书，随意填): " HY2_DRAFT_EMAIL || return 1
        [[ -z "${HY2_DRAFT_EMAIL}" ]] && HY2_DRAFT_EMAIL="admin@${HY2_DRAFT_DOMAIN}"
        if ! is_valid_email "${HY2_DRAFT_EMAIL}"; then
            err "邮箱格式无效，请重新输入。"
            sleep 2
            return 1
        fi

        HY2_DRAFT_SNI="${HY2_DRAFT_DOMAIN}"
        HY2_DRAFT_INSECURE="false"
    else
        pick_self_signed_sni || return 1
        HY2_DRAFT_SNI="${PICKED_SNI}"
        if ! is_valid_domain "${HY2_DRAFT_SNI}"; then
            err "SNI 域名格式无效，请输入有效域名。"
            sleep 2
            return 1
        fi
        HY2_DRAFT_INSECURE="true"
    fi
}

# shellcheck shell=bash
# 职责: Hysteria2 配置变更的准备、证书应用与启用

prepare_hy2_config_change() {
    if ! mkdir -p "${HY2_CONF_DIR}"; then
        err "创建配置目录失败: ${HY2_CONF_DIR}"
        sleep 2
        return 1
    fi
    set_config_dir_permissions
    if ! backup_runtime_files; then
        err "备份当前配置失败，已中止以避免覆盖现有配置。"
        sleep 2
        return 1
    fi
}

apply_hy2_ca_config() {
    local port="$1"
    local domain="$2"
    local email="$3"
    local password="$4"
    local masquerade_url="$5"

    if ! rm -f -- "${HY2_CONF_DIR}/server.crt" "${HY2_CONF_DIR}/server.key"; then
        abort_pending_config_change "清理旧自签证书失败"
        sleep 2
        return 1
    fi
    if ! write_ca_config "${port}" "${domain}" "${email}" "${password}" "${masquerade_url}"; then
        abort_pending_config_change "写入 CA 配置失败"
        sleep 2
        return 1
    fi
    set_server_config_permissions
}

apply_hy2_self_signed_config() {
    local port="$1"
    local password="$2"
    local masquerade_url="$3"
    local sni="$4"

    msg "正在生成高强度自签名证书..."
    if ! generate_self_signed_certificate "${sni}"; then
        abort_pending_config_change "自签证书生成失败"
        sleep 2
        return 1
    fi

    if ! get_certificate_sha256 "${HY2_CONF_DIR}/server.crt" >/dev/null; then
        abort_pending_config_change "无法计算自签证书 SHA-256 指纹"
        sleep 2
        return 1
    fi

    set_tls_file_permissions

    if ! write_self_signed_config "${port}" "${password}" "${masquerade_url}"; then
        abort_pending_config_change "写入自签配置失败"
        sleep 2
        return 1
    fi
    set_server_config_permissions
}

activate_hy2_config() {
    local port="$1"
    local password="$2"
    local sni="$3"
    local insecure="$4"
    local up_mbps="$5"
    local down_mbps="$6"
    local server_ip

    server_ip="$(fetch_server_ip)"
    if [[ -z "${server_ip}" ]]; then
        abort_pending_config_change "无法获取服务器 IP"
        sleep 2
        return 1
    fi

    if ! write_meta_info "${server_ip}" "${port}" "${password}" "${sni}" "${insecure}" "${up_mbps}" "${down_mbps}"; then
        abort_pending_config_change "写入节点元数据失败"
        sleep 2
        return 1
    fi
    chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true

    msg "检测到服务运行用户: $(get_service_run_user)"
    msg "正在重启 Hysteria2 服务以应用新配置..."
    if ! restart_service_with_rollback; then
        sleep 2
        return 1
    fi
    sleep 2
    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        ok "Hysteria2 节点配置并启动成功！"
    else
        err "启动失败！可能是端口被占用，或 CA 证书申请失败。请使用菜单 (4) 查看日志。"
        show_service_failure_hint
        err "检测到服务未保持运行，正在尝试自动回滚到上一版配置..."
        if restore_runtime_files && systemctl restart "${HY2_SERVICE}"; then
            err "已自动回滚到上一版配置，本次变更未生效。"
        else
            err "自动回滚失败，请手动检查配置与日志。"
        fi
        show_recent_service_logs
        sleep 3
        return 1
    fi
    sleep 2
}

# shellcheck shell=bash
# 职责: Hysteria2 交互配置流程编排

config_hy2() {
    if ! ensure_hy2_core_installed; then
        sleep 2
        return 1
    fi

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 节点配置 ---${_plain}"
    print_line

    reset_hy2_config_draft
    if ! collect_hy2_connection_settings; then
        return 1
    fi
    if ! collect_hy2_certificate_settings; then
        return 1
    fi

    if ! prepare_hy2_config_change; then
        return 1
    fi

    if [[ "${HY2_DRAFT_CERT_TYPE}" == "1" ]]; then
        if ! apply_hy2_ca_config \
            "${HY2_DRAFT_PORT}" \
            "${HY2_DRAFT_DOMAIN}" \
            "${HY2_DRAFT_EMAIL}" \
            "${HY2_DRAFT_PASSWORD}" \
            "${HY2_DRAFT_MASQUERADE_URL}"; then
            return 1
        fi
    else
        if ! apply_hy2_self_signed_config \
            "${HY2_DRAFT_PORT}" \
            "${HY2_DRAFT_PASSWORD}" \
            "${HY2_DRAFT_MASQUERADE_URL}" \
            "${HY2_DRAFT_SNI}"; then
            return 1
        fi
    fi

    activate_hy2_config \
        "${HY2_DRAFT_PORT}" \
        "${HY2_DRAFT_PASSWORD}" \
        "${HY2_DRAFT_SNI}" \
        "${HY2_DRAFT_INSECURE}" \
        "${HY2_DRAFT_UP_MBPS}" \
        "${HY2_DRAFT_DOWN_MBPS}"
}

# shellcheck shell=bash
# 职责: Hysteria2 分享链接

render_hysteria2_share_url() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local sni="$4"
    local insecure="$5"
    local cert_sha="${6:-}"
    local query

    case "${insecure}" in
        true) ;;
        false) ;;
        *) return 1 ;;
    esac

    if [[ -n "${cert_sha}" ]]; then
        cert_sha="$(normalize_certificate_sha256 "${cert_sha}")" || return 1
    fi
    if [[ "${insecure}" == "true" && -z "${cert_sha}" ]]; then
        return 1
    fi

    query="sni=$(url_encode "${sni}")"
    if [[ "${insecure}" == "true" ]]; then
        query+="&insecure=1"
    fi
    if [[ -n "${cert_sha}" ]]; then
        query+="&pinSHA256=${cert_sha}&pcs=${cert_sha}"
    fi

    printf 'hysteria2://%s@%s:%s/?%s#hy2ctl' \
        "$(url_encode "${password}")" \
        "$(format_host_for_url "${ip}")" \
        "${port}" \
        "${query}"
}

# shellcheck shell=bash
# 职责: Sing-box Hysteria2 出站与证书公钥固定字段

render_singbox_public_key_field() {
    local insecure="$1"
    local public_key_sha="${2:-}"
    local indent="$3"

    case "${insecure}" in
        true)
            is_valid_certificate_public_key_sha256 "${public_key_sha}" || return 1
            ;;
        false) ;;
        *) return 1 ;;
    esac
    if [[ -n "${public_key_sha}" ]]; then
        is_valid_certificate_public_key_sha256 "${public_key_sha}" || return 1
        printf ',\n%s"certificate_public_key_sha256": ["%s"]' "${indent}" "${public_key_sha}"
    fi
}

render_singbox_outbound_snippet() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_sha="${8:-}"
    local public_key_field

    public_key_field="$(render_singbox_public_key_field "${insecure}" "${public_key_sha}" "    ")" || return 1

    cat << EOF
{
  "type": "hysteria2",
  "tag": "proxy",
  "server": "${json_ip}",
  "server_port": ${port},
  "up_mbps": ${up_mbps},
  "down_mbps": ${down_mbps},
  "password": "${json_password}",
  "tls": {
    "enabled": true,
    "server_name": "${json_sni}",
    "insecure": ${insecure}${public_key_field}
  }
}
EOF
}

render_singbox_outbounds_section() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_field="$8"

    cat << EOF
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${json_ip}",
      "server_port": ${port},
      "up_mbps": ${up_mbps},
      "down_mbps": ${down_mbps},
      "password": "${json_password}",
      "tls": {
        "enabled": true,
        "server_name": "${json_sni}",
        "insecure": ${insecure}${public_key_field}
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
EOF
}

# shellcheck shell=bash
# 职责: Sing-box DNS 配置分段

render_singbox_dns_section() {
    cat << 'EOF'
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "cf",
        "server": "1.1.1.1",
        "detour": "proxy"
      },
      {
        "type": "udp",
        "tag": "local",
        "server": "223.5.5.5"
      }
    ],
    "rules": [
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      },
      {
        "rule_set": "geosite-cn",
        "action": "route",
        "server": "local"
      }
    ],
    "final": "cf",
    "strategy": "ipv4_only"
  },
EOF
}

# shellcheck shell=bash
# 职责: Sing-box 路由规则与远程规则集分段

render_singbox_route_section() {
    cat << 'EOF'
  "route": {
    "default_domain_resolver": "cf",
    "default_http_client": "rule-set-proxy",
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-cn",
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      }
    ],
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geosite-category-ads-all",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  },
EOF
}

# shellcheck shell=bash
# 职责: Sing-box 完整配置模板组合

render_singbox_http_clients_section() {
    cat << 'EOF'
  "http_clients": [
    {
      "tag": "rule-set-proxy",
      "detour": "proxy"
    }
  ],
EOF
}

render_singbox_inbounds_section() {
    cat << 'EOF'
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false
    }
  ],
EOF
}

render_singbox_experimental_section() {
    cat << 'EOF'
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
EOF
}

render_singbox_full_template() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_sha="${8:-}"
    local public_key_field

    public_key_field="$(render_singbox_public_key_field "${insecure}" "${public_key_sha}" "        ")" || return 1

    # 校验证书固定材料后顺序输出；调用方必须检查返回码，不得发布失败的部分输出。
    printf '{\n' || return 1
    render_singbox_http_clients_section || return 1
    render_singbox_dns_section || return 1
    render_singbox_inbounds_section || return 1
    render_singbox_outbounds_section "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${public_key_field}" || return 1
    render_singbox_route_section || return 1
    render_singbox_experimental_section || return 1
    printf '}\n'
}

# shellcheck shell=bash
# 职责: Sing-box 完整模板展示入口

show_singbox_template() {
    if ! require_meta_info; then
        return
    fi

    local json_ip json_password json_sni cert_public_key_sha=""
    if [[ "${insecure}" == "true" ]]; then
        cert_public_key_sha="$(get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
        if [[ -z "${cert_public_key_sha}" ]]; then
            err "自签证书公钥指纹读取失败，无法安全生成 Sing-box 配置。"
            echo -e "  请通过主菜单 (1) 重新配置自签证书后再导出。"
            wait_return
            return 1
        fi
    fi
    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"

    clear
    print_line
    echo -e "     ${_green}--- Sing-box 完整模板 (Android/iOS / 1.14+) ---${_plain}"
    print_line
    if ! render_singbox_full_template "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${cert_public_key_sha}"; then
        err "生成 Sing-box 完整模板失败，请重新配置节点。"
    fi
    print_line
    wait_return
}

# shellcheck shell=bash
# 职责: v2rayN 配置片段与兼容提醒

render_v2rayn_yaml_snippet() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local up_mbps="$4"
    local down_mbps="$5"
    local sni="$6"
    local insecure="$7"
    local cert_sha="${8:-}"
    local yaml_server yaml_password yaml_sni

    yaml_server="$(yaml_single_quote "$(format_host_for_url "${ip}"):${port}")"
    yaml_password="$(yaml_single_quote "${password}")"
    yaml_sni="$(yaml_single_quote "${sni}")"

    cat << EOF
server: ${yaml_server}
auth: ${yaml_password}
bandwidth:
  up: ${up_mbps} mbps
  down: ${down_mbps} mbps
tls:
  sni: ${yaml_sni}
  insecure: ${insecure}
EOF
    if [[ -n "${cert_sha}" ]]; then
        printf '  pinSHA256: %s\n' "${cert_sha}"
    fi
    cat << EOF
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:8080
EOF
}

print_v2rayn_insecure_notice() {
    print_line
    echo -e "${_yellow}[v2rayN / Xray 自签证书提醒]${_plain}"
    echo -e "  原生 Hysteria2 使用 insecure=1 与 pinSHA256 验证自签证书。"
    echo -e "  v2rayN / Xray 使用 pcs 映射 pinnedPeerCertSha256。"
    echo -e "  使用 Xray 时请确保：v2rayN >= 7.17.1，Xray-core >= 26.2.6。"
    echo -e "  请使用 v2rayN >= 7.24.9，以修复旧版下载器的中间人攻击风险。"
    echo -e "  Sing-box 自签配置使用公钥固定，请使用 Sing-box >= 1.13.0。"
    echo -e "  分享链接已移除 allowInsecure，不再依赖已废弃的跳过验证字段。"
    echo -e "  重新生成自签证书后指纹会变化，客户端必须重新导入节点。"
}

# shellcheck shell=bash
# 职责: 客户端节点参数与证书指纹摘要展示

print_client_summary() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"

    clear
    print_line
    echo -e "               ${_green}--- Hysteria2 客户端配置 ---${_plain}"
    print_line
    echo -e "  [*] 服务器 IP : ${_yellow}${ip}${_plain}"
    echo -e "  [*] 端口      : ${_yellow}${port}${_plain}"
    echo -e "  [*] 密码      : ${_yellow}${password}${_plain}"
    echo -e "  [*] SNI伪装   : ${_yellow}${sni}${_plain}"
    echo -e "  [*] 跳过证书  : ${_yellow}${insecure}${_plain} (自签必须为true)"
    if [[ "${insecure}" == "true" ]]; then
        if [[ -n "${cert_sha}" ]]; then
            echo -e "  [*] 证书指纹  : ${_yellow}${cert_sha}${_plain}"
        else
            echo -e "  [!] 证书指纹  : ${_red}读取失败，已禁止导出客户端链接${_plain}"
        fi
        if [[ -n "${cert_public_key_sha}" ]]; then
            echo -e "  [*] 公钥指纹  : ${_yellow}${cert_public_key_sha}${_plain} (Sing-box)"
        else
            echo -e "  [!] 公钥指纹  : ${_red}读取失败，已禁止导出 Sing-box 配置${_plain}"
        fi
    fi
    echo -e "  [*] 上行带宽  : ${_yellow}${up_mbps}${_plain} Mbps"
    echo -e "  [*] 下行带宽  : ${_yellow}${down_mbps}${_plain} Mbps"
    print_line
}

# shellcheck shell=bash
# 职责: 客户端导出前安全校验与多格式配置输出

ensure_client_export_material() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"

    if [[ "${insecure}" == "true" && ( -z "${cert_sha}" || -z "${cert_public_key_sha}" ) ]]; then
        err "自签证书校验值读取失败，无法安全生成客户端配置。"
        echo -e "  请通过主菜单 (1) 重新配置自签证书后再导出。"
        wait_return
        return 1
    fi
}

print_client_exports() {
    local cert_sha="$1"
    local cert_public_key_sha="$2"
    local hy2_url json_ip json_password json_sni

    if ! hy2_url="$(render_hysteria2_share_url "${ip}" "${port}" "${password}" "${sni}" "${insecure}" "${cert_sha}")"; then
        err "生成 Hysteria2 分享链接失败，请重新配置节点。"
        wait_return
        return 1
    fi

    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"
    echo -e "${_green}[Link] 一键导入链接 (推荐 V2rayN / NekoBox / Clash):${_plain}"
    echo -e "${hy2_url}"
    print_line

    echo -e "${_green}[JSON] Sing-box 1.13+ (Android/iOS) 专属 Outbound 模块:${_plain}"
    if ! render_singbox_outbound_snippet "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${cert_public_key_sha}"; then
        err "生成 Sing-box Outbound 失败，请重新配置节点。"
        wait_return
        return 1
    fi
    print_line
    echo -e "${_green}[YAML] v2rayN / nekoray 自定义配置片段:${_plain}"
    render_v2rayn_yaml_snippet "${ip}" "${port}" "${password}" "${up_mbps}" "${down_mbps}" "${sni}" "${insecure}" "${cert_sha}"
}

# shellcheck shell=bash
# 职责: 客户端配置查看流程编排

show_info() {
    if ! require_meta_info; then
        return
    fi

    local cert_sha="" cert_public_key_sha=""
    if [[ "${insecure}" == "true" ]]; then
        cert_sha="$(get_certificate_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
        cert_public_key_sha="$(get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
    fi

    print_client_summary "${cert_sha}" "${cert_public_key_sha}"

    if ! ensure_client_export_material "${cert_sha}" "${cert_public_key_sha}"; then
        return 1
    fi

    if [[ "${insecure}" == "true" ]]; then
        print_v2rayn_insecure_notice
    fi

    if ! print_client_exports "${cert_sha}" "${cert_public_key_sha}"; then
        return 1
    fi
    print_line
    wait_return
}

# shellcheck shell=bash
# 职责: Hysteria2 服务管理与文件路径速查展示

show_cheatsheet() {
    clear
    print_line
    echo -e "               ${_green}--- 常用指令速查 ---${_plain}"
    print_line
    echo -e "${_green}[服务器管理]${_plain}"
    echo -e "bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/install.sh)"
    echo -e "hy2 --install-core"
    echo -e "bash <(curl -fsSL https://get.hy2.sh/)"
    echo -e "systemctl start ${HY2_SERVICE}"
    echo -e "systemctl restart ${HY2_SERVICE}"
    echo -e "systemctl status ${HY2_SERVICE} --no-pager -l"
    echo -e "systemctl stop ${HY2_SERVICE}"
    echo -e "systemctl enable ${HY2_SERVICE}"
    echo -e "journalctl -u ${HY2_SERVICE} --no-pager -n 100 -f"
    print_line
    echo -e "${_green}[自签证书生成]${_plain}"
    echo -e "openssl req -x509 -nodes -newkey ec \\"
    echo -e "  -pkeyopt ec_paramgen_curve:prime256v1 \\"
    echo -e "  -keyout ${HY2_CONF_DIR}/server.key -out ${HY2_CONF_DIR}/server.crt \\"
    echo -e "  -subj \"/CN=bing.com\" -days 36500 \\"
    echo -e "  -addext \"subjectAltName=DNS:bing.com\" \\"
    echo -e "  -addext \"basicConstraints=critical,CA:FALSE\" \\"
    echo -e "  -addext \"extendedKeyUsage=serverAuth\""
    print_line
    echo -e "${_green}[配置文件路径]${_plain}"
    echo -e "服务配置: ${HY2_CONF_FILE}"
    echo -e "元数据  : ${HY2_META_FILE}"
    print_line
    wait_return
}

# shellcheck shell=bash
# 职责: 管理面板单文件更新与回滚

verify_downloaded_panel() {
    local file="$1"
    local downloaded_version
    [[ -s "${file}" ]] || return 1
    head -n 1 "${file}" | grep -q '^#!/bin/bash' || return 1
    grep -q 'main_menu' "${file}" || return 1
    grep -q 'hy2ctl 管理面板' "${file}" || return 1
    bash -n "${file}" >/dev/null 2>&1 || return 1
    downloaded_version="$(extract_panel_version "${file}")"
    [[ -n "${downloaded_version}" ]] || return 1
    return 0
}

extract_panel_version() {
    local file="$1"
    sed -n 's/^sh_ver="\(v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' "${file}" | head -n 1
}

backup_existing_panel() {
    local backup_file
    if [[ ! -f "${PANEL_TARGET_BIN}" ]]; then
        return 0
    fi
    backup_file="$(mktemp "${PANEL_BACKUP_PREFIX}.$(date '+%Y%m%d-%H%M%S').XXXXXX")" || return 1
    if ! cp -p -- "${PANEL_TARGET_BIN}" "${backup_file}"; then
        rm -f -- "${backup_file}"
        return 1
    fi
    printf '%s\n' "${backup_file}"
}

restore_panel_backup() {
    local backup_file="$1"
    [[ -n "${backup_file}" && -f "${backup_file}" ]] || return 1
    cp -p -- "${backup_file}" "${PANEL_TARGET_BIN}"
}

update_panel_script() {
    local confirm
    clear
    print_line
    echo -e "             ${_green}--- 更新管理面板脚本 ---${_plain}"
    print_line
    echo -e "当前版本: ${_yellow}${sh_ver}${_plain}"
    echo -e "目标路径: ${_yellow}${PANEL_TARGET_BIN}${_plain}"
    print_line
    read_input " => 确认从 GitHub 拉取最新面板脚本并覆盖本地 hy2？(y/n): " confirm || return 1
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        msg "已取消更新。"
        sleep 1
        return 0
    fi

    local tmp_file
    local backup_file=""
    local downloaded_version
    tmp_file="$(mktemp "${PANEL_TARGET_BIN}.tmp.XXXXXX")" || {
        err "创建临时文件失败。"
        sleep 2
        return 1
    }

    msg "正在下载最新管理面板脚本..."
    if ! download_script "${PANEL_UPDATE_URL}" "${tmp_file}"; then
        rm -f "${tmp_file}"
        err "下载失败，请检查网络或稍后重试。"
        sleep 2
        return 1
    fi

    if ! verify_downloaded_panel "${tmp_file}"; then
        rm -f "${tmp_file}"
        err "下载内容校验失败，已停止覆盖本地脚本。"
        sleep 2
        return 1
    fi

    downloaded_version="$(extract_panel_version "${tmp_file}")"
    msg "已下载版本: ${downloaded_version}"

    if [[ -f "${PANEL_TARGET_BIN}" ]]; then
        msg "正在备份当前面板脚本..."
        if ! backup_file="$(backup_existing_panel)"; then
            rm -f "${tmp_file}"
            err "备份当前脚本失败，已停止更新。"
            sleep 2
            return 1
        fi
        [[ -n "${backup_file}" ]] && msg "备份路径: ${backup_file}"
    fi

    if ! chmod +x "${tmp_file}" || ! mv -f "${tmp_file}" "${PANEL_TARGET_BIN}"; then
        rm -f "${tmp_file}"
        if [[ -n "${backup_file}" ]]; then
            restore_panel_backup "${backup_file}" >/dev/null 2>&1 || true
        fi
        err "写入 ${PANEL_TARGET_BIN} 失败，请检查权限。"
        sleep 2
        return 1
    fi

    ok "管理面板脚本已更新。重新输入 hy2 即可使用新版。"
    wait_return
}

show_update_menu() {
    clear
    print_line
    echo -e "              ${_green}--- 面板与内核更新 ---${_plain}"
    print_line
    echo -e "    (1) 安装/更新 Hysteria2 内核"
    echo -e "    (2) 更新 hy2ctl 管理面板"
    echo -e "    (0) 返回主菜单"
    print_line

    local action
    read_input " => 请选择操作 [0-2]: " action || return 0
    case "${action}" in
        1)
            install_hy2_core
            wait_return
            ;;
        2) update_panel_script ;;
        0) return 0 ;;
        *)
            err "输入错误"
            sleep 1
            ;;
    esac
}

# shellcheck shell=bash
# 职责: 诊断上下文、计数与建议去重

diagnostic_reset_context() {
    DIAG_OK_COUNT=0
    DIAG_WARN_COUNT=0
    DIAG_FAIL_COUNT=0
    DIAG_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    DIAG_FILE="${HY2_DIAG_DIR}/hy2-diagnose-${DIAG_TIMESTAMP}.log"
    DIAG_CONCLUSIONS=()
    DIAG_SUGGESTIONS=()
    DIAG_COMMANDS=()
    : > "${DIAG_FILE}" 2>/dev/null || DIAG_FILE=""
}

diagnostic_log() {
    local text="$1"
    if [[ -n "${DIAG_FILE}" ]]; then
        echo -e "${text}" >> "${DIAG_FILE}"
    fi
}

diagnostic_print_result() {
    local level="$1"
    local text="$2"
    case "${level}" in
        OK)
            echo -e "${_green}[OK]${_plain} ${text}"
            diagnostic_log "[OK] ${text}"
            DIAG_OK_COUNT=$((DIAG_OK_COUNT + 1))
            ;;
        WARN)
            echo -e "${_yellow}[WARN]${_plain} ${text}"
            diagnostic_log "[WARN] ${text}"
            DIAG_WARN_COUNT=$((DIAG_WARN_COUNT + 1))
            ;;
        FAIL)
            echo -e "${_red}[FAIL]${_plain} ${text}"
            diagnostic_log "[FAIL] ${text}"
            DIAG_FAIL_COUNT=$((DIAG_FAIL_COUNT + 1))
            ;;
    esac
}

diagnostic_add_item() {
    local conclusion="$1"
    local suggestion="$2"
    local command_hint="$3"
    local existing
    for existing in "${DIAG_CONCLUSIONS[@]}"; do
        if [[ "${existing}" == "${conclusion}" ]]; then
            return 0
        fi
    done
    DIAG_CONCLUSIONS+=("${conclusion}")
    DIAG_SUGGESTIONS+=("${suggestion}")
    DIAG_COMMANDS+=("${command_hint}")
}

# shellcheck shell=bash
# 职责: Hysteria2 内核、服务、配置与网络诊断检查

diagnostic_check_core() {
    local core_version

    if ensure_hy2_core_installed; then
        core_version="$(get_hy2_core_version 2>/dev/null || true)"
        if [[ -z "${core_version}" ]]; then
            diagnostic_print_result "WARN" "已检测到 Hysteria2 内核，但无法读取版本。"
        elif ! version_at_least "${core_version}" "${HY2_SECURITY_BASELINE_VERSION}"; then
            diagnostic_print_result "WARN" "Hysteria2 内核版本 ${core_version} 低于安全基线 v${HY2_SECURITY_BASELINE_VERSION}，存在高危安全风险。"
            diagnostic_add_item \
                "Hysteria2 内核版本存在高危安全风险。" \
                "立即更新到 v${RECOMMENDED_HY2_VERSION} 或更高版本，避免旧版本中的访问控制绕过与拒绝服务风险。" \
                "菜单 (11) -> 安装/更新 Hysteria2 内核"
        elif version_at_least "${core_version}" "${RECOMMENDED_HY2_VERSION}"; then
            diagnostic_print_result "OK" "Hysteria2 内核版本: ${core_version}。"
        else
            diagnostic_print_result "WARN" "Hysteria2 内核版本 ${core_version} 低于建议版本 v${RECOMMENDED_HY2_VERSION}。"
            diagnostic_add_item \
                "Hysteria2 内核版本较旧。" \
                "建议更新，以获得移动端快速重连、IPv6 mimic 与小 MTU 稳定性修复。" \
                "菜单 (11) -> 安装/更新 Hysteria2 内核"
        fi
    else
        diagnostic_print_result "FAIL" "未检测到 Hysteria2 内核，请通过菜单 (11) 安装。"
        diagnostic_add_item \
            "未安装 Hysteria2 内核。" \
            "先安装内核，再进行节点配置与启动服务。" \
            "菜单 (11) -> 安装/更新 Hysteria2 内核"
    fi
}

diagnostic_check_service() {
    if systemctl is-enabled "${HY2_SERVICE}" >/dev/null 2>&1; then
        diagnostic_print_result "OK" "服务已设置开机自启。"
    else
        diagnostic_print_result "WARN" "服务未设置开机自启，可执行: systemctl enable ${HY2_SERVICE}"
        diagnostic_add_item \
            "服务未开启开机自启。" \
            "建议开启自启，避免重启后节点离线。" \
            "systemctl enable ${HY2_SERVICE}"
    fi

    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        diagnostic_print_result "OK" "服务当前状态: 运行中。"
    else
        diagnostic_print_result "WARN" "服务当前未运行，可执行菜单 (3) 启动/重启。"
        diagnostic_add_item \
            "服务当前未运行。" \
            "先尝试启动服务，若失败再看实时日志定位原因。" \
            "systemctl restart ${HY2_SERVICE} && journalctl -u ${HY2_SERVICE} --no-pager -n 60"
    fi
}

diagnostic_check_runtime_files() {
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        diagnostic_print_result "OK" "配置文件存在: ${HY2_CONF_FILE}"
    else
        diagnostic_print_result "FAIL" "配置文件不存在: ${HY2_CONF_FILE}"
        diagnostic_add_item \
            "服务配置文件缺失。" \
            "重新执行节点配置生成 config.yaml。" \
            "菜单 (1) 配置 Hysteria2 节点 (CA / 自签)"
    fi

    if read_meta_info; then
        diagnostic_print_result "OK" "节点元数据存在且可解析。"
    else
        diagnostic_print_result "WARN" "节点元数据缺失或损坏，建议重新执行菜单 (1)。"
        diagnostic_add_item \
            "节点元数据缺失或损坏。" \
            "重新生成节点配置，确保分享链接参数准确。" \
            "菜单 (1) 配置 Hysteria2 节点 (CA / 自签)"
    fi
}

diagnostic_check_server_config() {
    local listen_port cert_path key_path

    [[ -f "${HY2_CONF_FILE}" ]] || return 0

    listen_port="$(sed -n 's/^listen:[[:space:]]*:\([0-9]\+\).*/\1/p' "${HY2_CONF_FILE}" | head -n 1)"
    if [[ -n "${listen_port}" ]]; then
        diagnostic_print_result "OK" "监听端口配置为: ${listen_port}"
        if command -v ss >/dev/null 2>&1; then
            if ss -lun 2>/dev/null | grep -qE "[\:\.]${listen_port}[[:space:]]"; then
                diagnostic_print_result "OK" "检测到 UDP 端口 ${listen_port} 正在监听。"
            else
                diagnostic_print_result "WARN" "未检测到 UDP 端口 ${listen_port} 监听，可能服务未启动。"
                diagnostic_add_item \
                    "未检测到 UDP 端口 ${listen_port} 监听。" \
                    "可能服务未运行或端口被占用，请先检查服务与端口占用。" \
                    "ss -lntup | grep -E \"[:.]${listen_port}[[:space:]]\""
            fi
        else
            diagnostic_print_result "WARN" "系统未安装 ss，跳过端口监听检查。"
        fi
    else
        diagnostic_print_result "WARN" "未能从配置中解析 listen 端口。"
        diagnostic_add_item \
            "无法从配置解析 listen 端口。" \
            "请检查 config.yaml 语法与 listen 字段格式。" \
            "hysteria server -c ${HY2_CONF_FILE}"
    fi

    if grep -q '^tls:' "${HY2_CONF_FILE}"; then
        cert_path="$(sed -n 's/^[[:space:]]*cert:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
        key_path="$(sed -n 's/^[[:space:]]*key:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
        if [[ -n "${cert_path}" && -f "${cert_path}" ]]; then
            diagnostic_print_result "OK" "自签证书文件存在: ${cert_path}"
        else
            diagnostic_print_result "FAIL" "自签证书文件缺失。"
            diagnostic_add_item \
                "自签证书文件缺失。" \
                "重新执行自签配置生成证书，或检查证书路径。" \
                "菜单 (1) -> 自签模式重新生成"
        fi
        if [[ -n "${key_path}" && -f "${key_path}" ]]; then
            diagnostic_print_result "OK" "自签私钥文件存在: ${key_path}"
        else
            diagnostic_print_result "FAIL" "自签私钥文件缺失。"
            diagnostic_add_item \
                "自签私钥文件缺失。" \
                "重新执行自签配置生成私钥，确认文件权限可读。" \
                "菜单 (1) -> 自签模式重新生成"
        fi
    elif grep -q '^acme:' "${HY2_CONF_FILE}"; then
        diagnostic_print_result "OK" "当前为 CA 证书模式。"
    else
        diagnostic_print_result "WARN" "未检测到 tls/acme 配置块，请确认配置正确。"
        diagnostic_add_item \
            "配置未识别到 tls/acme 证书块。" \
            "配置内容可能异常，建议重新生成节点配置。" \
            "菜单 (1) 重新配置节点"
    fi
}

diagnostic_check_public_ip() {
    local probe_ip

    probe_ip="$(fetch_server_ip)"
    if [[ -n "${probe_ip}" ]]; then
        diagnostic_print_result "OK" "公网 IP 探测成功: ${probe_ip}"
        if [[ -n "${ip:-}" && "${ip}" != "${probe_ip}" ]]; then
            diagnostic_print_result "WARN" "元数据 IP(${ip}) 与当前探测 IP(${probe_ip}) 不一致。"
            diagnostic_add_item \
                "元数据 IP 与当前公网 IP 不一致。" \
                "客户端可能连向旧 IP，建议更新客户端配置。" \
                "菜单 (2) 重新获取分享链接并覆盖客户端配置"
        fi
    else
        diagnostic_print_result "WARN" "公网 IP 探测失败，请检查网络连接。"
        diagnostic_add_item \
            "公网 IP 探测失败。" \
            "可能是本机网络受限或 DNS 问题，先验证基础网络连通。" \
            "curl -4 https://api.ipify.org && curl -6 https://api64.ipify.org"
    fi
}

# shellcheck shell=bash
# 职责: 诊断结果摘要、建议与报告导出

diagnostic_render_summary() {
    local line_status summary_plain idx

    print_line
    if (( DIAG_FAIL_COUNT > 0 )); then
        line_status="${_red}诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / ${DIAG_FAIL_COUNT} FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / ${DIAG_FAIL_COUNT} FAIL"
    elif (( DIAG_WARN_COUNT > 0 )); then
        line_status="${_yellow}诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / 0 FAIL"
    else
        line_status="${_green}诊断结果: ${DIAG_OK_COUNT} OK / 0 WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / 0 WARN / 0 FAIL"
    fi
    echo -e "${line_status}"
    diagnostic_log "${summary_plain}"
    echo -e "${_blue}[分级]${_plain} 阻断项(FAIL): ${DIAG_FAIL_COUNT} | 警告项(WARN): ${DIAG_WARN_COUNT} | 建议项: ${#DIAG_CONCLUSIONS[@]}"
    diagnostic_log "分级: 阻断项(FAIL)=${DIAG_FAIL_COUNT}, 警告项(WARN)=${DIAG_WARN_COUNT}, 建议项=${#DIAG_CONCLUSIONS[@]}"
    if (( ${#DIAG_CONCLUSIONS[@]} > 0 )); then
        print_line
        echo -e "${_yellow}[诊断建议]${_plain} 结论 + 建议 + 命令"
        diagnostic_log "--- 诊断建议 ---"
        for idx in "${!DIAG_CONCLUSIONS[@]}"; do
            echo -e "  [结论] ${DIAG_CONCLUSIONS[${idx}]}"
            echo -e "  [建议] ${DIAG_SUGGESTIONS[${idx}]}"
            echo -e "  [命令] ${DIAG_COMMANDS[${idx}]}"
            echo -e ""
            diagnostic_log "[结论] ${DIAG_CONCLUSIONS[${idx}]}"
            diagnostic_log "[建议] ${DIAG_SUGGESTIONS[${idx}]}"
            diagnostic_log "[命令] ${DIAG_COMMANDS[${idx}]}"
            diagnostic_log ""
        done
    fi
    if [[ -n "${DIAG_FILE}" ]]; then
        cp -f "${DIAG_FILE}" "${HY2_DIAG_LATEST}" >/dev/null 2>&1 || true
        echo -e "${_blue}[信息]${_plain} 诊断报告已导出: ${DIAG_FILE}"
        echo -e "${_blue}[信息]${_plain} 最新报告快捷路径: ${HY2_DIAG_LATEST}"
    else
        echo -e "${_yellow}[提示]${_plain} 诊断报告导出失败，仅显示终端结果。"
    fi
    print_line
}

# shellcheck shell=bash
# 职责: 环境诊断与报告查看

show_diagnostics() {
    diagnostic_reset_context

    clear
    print_line
    echo -e "             ${_green}--- 一键环境诊断 ---${_plain}"
    print_line
    if [[ -n "${DIAG_FILE}" ]]; then
        diagnostic_log "=== hy2ctl Diagnose @ ${DIAG_TIMESTAMP} ==="
        diagnostic_log "config_file=${HY2_CONF_FILE}"
        diagnostic_log "meta_file=${HY2_META_FILE}"
        diagnostic_log "service=${HY2_SERVICE}"
    fi

    diagnostic_check_core

    diagnostic_check_service

    diagnostic_check_runtime_files

    diagnostic_check_server_config

    diagnostic_check_public_ip

    diagnostic_render_summary
    wait_return
}

show_latest_diagnostics_report() {
    clear
    print_line
    echo -e "            ${_green}--- 最近诊断报告 ---${_plain}"
    print_line
    if [[ ! -f "${HY2_DIAG_LATEST}" ]]; then
        err "未找到最近诊断报告。请先执行菜单 (8) 一键环境诊断。"
        print_line
        wait_return
        return
    fi
    cat "${HY2_DIAG_LATEST}"
    print_line
    wait_return
}

# shellcheck shell=bash
# 职责: 创建 Hysteria2 手动配置备份

create_manual_backup() {
    local ts backup_dir

    if [[ ! -f "${HY2_CONF_FILE}" ]]; then
        err "当前没有可备份的 config.yaml，请先完成节点配置。"
        return 1
    fi

    if ! mkdir -p "${HY2_BACKUP_DIR}"; then
        err "创建备份根目录失败: ${HY2_BACKUP_DIR}"
        return 1
    fi

    ts="$(date '+%Y%m%d-%H%M%S')"
    if ! backup_dir="$(mktemp -d "${HY2_BACKUP_DIR}/manual-${ts}.XXXXXX")"; then
        err "创建备份目录失败: ${backup_dir}"
        return 1
    fi

    if ! cp -p -- "${HY2_CONF_FILE}" "${backup_dir}/config.yaml"; then
        rm -rf -- "${backup_dir}"
        err "备份 config.yaml 失败。"
        return 1
    fi
    if [[ -f "${HY2_META_FILE}" ]] && ! cp -p -- "${HY2_META_FILE}" "${backup_dir}/meta.info"; then
        rm -rf -- "${backup_dir}"
        err "备份 meta.info 失败。"
        return 1
    fi

    if grep -q '^tls:' "${HY2_CONF_FILE}"; then
        if [[ ! -f "${HY2_CONF_DIR}/server.crt" || ! -f "${HY2_CONF_DIR}/server.key" ]]; then
            rm -rf -- "${backup_dir}"
            err "当前为自签模式，但证书或私钥缺失，已取消备份。"
            return 1
        fi
        if ! cp -p -- "${HY2_CONF_DIR}/server.crt" "${backup_dir}/server.crt" || \
            ! cp -p -- "${HY2_CONF_DIR}/server.key" "${backup_dir}/server.key"; then
            rm -rf -- "${backup_dir}"
            err "备份自签证书文件失败。"
            return 1
        fi
    fi

    ok "手动备份完成: ${backup_dir}"
    return 0
}

# shellcheck shell=bash
# 职责: 校验并恢复最近的 Hysteria2 手动备份

find_latest_manual_backup() {
    ls -1dt "${HY2_BACKUP_DIR}"/manual-* 2>/dev/null | head -n 1 || true
}

validate_manual_backup_dir() {
    local backup_dir="$1"

    if [[ -z "${backup_dir}" || ! -d "${backup_dir}" ]]; then
        err "未找到可恢复的手动备份。"
        return 1
    fi
    if [[ ! -f "${backup_dir}/config.yaml" ]]; then
        err "备份中缺少 config.yaml，已中止恢复: ${backup_dir}"
        return 1
    fi
    if grep -q '^tls:' "${backup_dir}/config.yaml" && \
        [[ ! -f "${backup_dir}/server.crt" || ! -f "${backup_dir}/server.key" ]]; then
        err "自签模式备份缺少证书或私钥，已中止恢复: ${backup_dir}"
        return 1
    fi
}

restore_manual_backup_files() {
    local backup_dir="$1"
    local backup_uses_tls="$2"
    local restore_failed=0

    cp -p -- "${backup_dir}/config.yaml" "${HY2_CONF_FILE}" || restore_failed=1
    if [[ -f "${backup_dir}/meta.info" ]]; then
        cp -p -- "${backup_dir}/meta.info" "${HY2_META_FILE}" || restore_failed=1
    else
        rm -f -- "${HY2_META_FILE}" || restore_failed=1
    fi
    if [[ "${backup_uses_tls}" -eq 1 ]]; then
        cp -p -- "${backup_dir}/server.crt" "${HY2_CONF_DIR}/server.crt" || restore_failed=1
        cp -p -- "${backup_dir}/server.key" "${HY2_CONF_DIR}/server.key" || restore_failed=1
    else
        rm -f -- "${HY2_CONF_DIR}/server.crt" "${HY2_CONF_DIR}/server.key" || restore_failed=1
    fi

    [[ "${restore_failed}" -eq 0 ]]
}

set_manual_restore_permissions() {
    local backup_uses_tls="$1"

    set_config_dir_permissions
    set_server_config_permissions
    if [[ -f "${HY2_META_FILE}" ]]; then
        chmod 600 "${HY2_META_FILE}" 2>/dev/null || true
    fi
    if [[ "${backup_uses_tls}" -eq 1 ]]; then
        set_tls_file_permissions
    fi
}

restore_latest_manual_backup() {
    local latest_dir
    local backup_uses_tls=0

    latest_dir="$(find_latest_manual_backup)"
    if ! validate_manual_backup_dir "${latest_dir}"; then
        return 1
    fi
    if grep -q '^tls:' "${latest_dir}/config.yaml"; then
        backup_uses_tls=1
    fi

    if ! backup_runtime_files; then
        err "无法备份当前运行配置，已中止恢复操作。"
        return 1
    fi

    if ! restore_manual_backup_files "${latest_dir}" "${backup_uses_tls}"; then
        if restore_runtime_files; then
            err "恢复备份文件失败，已恢复操作前配置。"
        else
            err "恢复备份文件失败，且无法恢复操作前配置，请立即检查 ${HY2_CONF_DIR}。"
        fi
        return 1
    fi

    set_manual_restore_permissions "${backup_uses_tls}"

    if systemctl restart "${HY2_SERVICE}" >/dev/null 2>&1; then
        ok "已恢复最近备份并重启服务: ${latest_dir}"
        return 0
    fi

    err "备份文件已恢复，但服务重启失败，正在回滚到操作前配置..."
    if restore_runtime_files && systemctl restart "${HY2_SERVICE}" >/dev/null 2>&1; then
        err "已恢复操作前配置，本次手动恢复未生效。"
    else
        err "自动回滚失败，请立即检查配置与服务日志。"
    fi
    return 1
}

# shellcheck shell=bash
# 职责: 手动备份与恢复菜单；实际操作位于 operations/backup_*.sh

show_backup_restore_menu() {
    local action
    while true; do
        clear
        print_line
        echo -e "           ${_green}--- 配置备份与恢复 ---${_plain}"
        print_line
        echo -e "    (1) 创建手动备份"
        echo -e "    (2) 恢复最近手动备份"
        echo -e "    (3) 查看手动备份列表"
        echo -e "    (0) 返回主菜单"
        print_line
        read_input " => 请选择操作 [0-3]: " action || return 0

        case "${action}" in
            1)
                create_manual_backup
                sleep 1
                ;;
            2)
                restore_latest_manual_backup
                sleep 2
                ;;
            3)
                echo -e "${_green}[备份列表]${_plain}"
                ls -1dt "${HY2_BACKUP_DIR}"/manual-* 2>/dev/null || echo "(空)"
                print_line
                wait_return
                ;;
            0) return 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# shellcheck shell=bash
# 职责: Hysteria2 服务控制菜单

service_control_menu() {
    local action
    while true; do
        clear
        print_line
        echo -e "               ${_green}--- 服务控制 ---${_plain}"
        print_line
        echo -e "    (1) 启动服务"
        echo -e "    (2) 停止服务"
        echo -e "    (3) 重启服务"
        echo -e "    (4) 查看状态"
        echo -e "    (0) 返回主菜单"
        print_line
        read_input " => 请选择操作 [0-4]: " action || return 0

        case "${action}" in
            1)
                if change_hy2_service_state start; then
                    ok "服务已启动。"
                else
                    err "启动失败，请检查日志。"
                fi
                sleep 1
                ;;
            2)
                if change_hy2_service_state stop; then
                    ok "服务已停止。"
                else
                    err "停止失败，请检查日志。"
                fi
                sleep 1
                ;;
            3)
                if change_hy2_service_state restart; then
                    ok "服务已重启。"
                else
                    err "重启失败，请检查日志。"
                fi
                sleep 1
                ;;
            4)
                if systemctl is-active --quiet "${HY2_SERVICE}"; then
                    ok "当前状态: 运行中"
                else
                    err "当前状态: 未运行"
                fi
                sleep 1
                ;;
            0) return 0 ;;
            *) err "输入错误"; sleep 1 ;;
        esac
    done
}

# shellcheck shell=bash
# 职责: 主菜单渲染、操作分派与交互循环；状态每次重绘实时获取

render_main_menu() {
    clear
    print_line
    echo -e "  ${_green}hy2ctl 管理面板 ${sh_ver} |  快捷启动: hy2${_plain}"
    print_line

    local status="${_red}未运行${_plain}"
    local core_version="未安装"
    if command -v hysteria &> /dev/null; then
        core_version="$(get_hy2_core_version 2>/dev/null || true)"
        [[ -z "$core_version" ]] && core_version="未知版本"

        if systemctl is-active --quiet "${HY2_SERVICE}"; then
            status="${_green}运行中${_plain}"
        fi
    fi

    echo -e "  内核版本: ${core_version}    服务状态: ${status}"
    print_sub_line
    echo -e "  节点核心管理"
    echo -e "    (1)  节点配置（CA / 自签）"
    echo -e "    (2)  客户端配置与分享"
    echo -e ""
    echo -e "  服务运行控制"
    echo -e "    (3)  服务启动与控制"
    echo -e "    (4)  实时运行日志"
    echo -e "    (5)  完全卸载清理"
    echo -e "    (6)  常用指令速查"
    echo -e "    (7)  Sing-box 完整模板"
    echo -e "    (8)  一键环境诊断"
    echo -e "    (9)  最近诊断报告"
    echo -e "    (10) 配置备份与恢复"
    echo -e "    (11) 面板与内核更新"
    echo -e "    (0)  退出面板"
    print_line
}

dispatch_main_menu() {
    case "$1" in
        1) config_hy2 ;;
        2) show_info ;;
        3)
            if ensure_hy2_core_installed; then
                service_control_menu
            else
                sleep 2
            fi
            ;;
        4)
            if ensure_hy2_core_installed; then
                journalctl -u "${HY2_SERVICE}" --no-pager -n 100 -f
            else
                sleep 2
            fi
            ;;
        5) uninstall_hy2 ;;
        6) show_cheatsheet ;;
        7) show_singbox_template ;;
        8) show_diagnostics ;;
        9) show_latest_diagnostics_report ;;
        10) show_backup_restore_menu ;;
        11) show_update_menu ;;
        *) err "输入错误"; sleep 1 ;;
    esac
}

main_menu() {
    local menu_num
    while true; do
        render_main_menu
        read_input " => 请选择操作 [0-11]: " menu_num || return 0
        [[ "${menu_num}" == "0" ]] && return 0
        dispatch_main_menu "${menu_num}"
    done
}

# shellcheck shell=bash
# 职责: 管理面板启动入口

# 入口运行
if [[ "${HY2_LIB_ONLY:-0}" != "1" ]]; then
    require_root
    preflight_check
    case "${1:-}" in
        --install-core) install_hy2_core ;;
        "") main_menu ;;
        *)
            err "未知参数: $1"
            exit 1
            ;;
    esac
fi
