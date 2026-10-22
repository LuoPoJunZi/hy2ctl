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

get_hy2_go_version() {
    local version_output line
    command -v hysteria >/dev/null 2>&1 || return 1
    version_output="$(hysteria version 2>/dev/null)" || return 1
    while IFS= read -r line; do
        # 只信版本命令的明确字段；不从库版本、开发版或厂商后缀猜测修复状态。
        if [[ "${line}" =~ ^Toolchain:[[:space:]]*(go1\.[0-9]+\.[0-9]+)[[:space:]]*$ ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done <<< "${version_output}"
    return 1
}

go_version_has_ca_mitigation() {
    local version="${1#go}"
    # CVE-2026-111943: https://go.dev/issue/82345
    # 必须分别比较维护分支，不能把 go1.27.0 当成高于 go1.26.10 的修复版。
    case "${version}" in
        1.26.*) version_at_least "${version}" "1.26.10" ;;
        1.27.*) version_at_least "${version}" "1.27.3" ;;
        *) version_at_least "${version}" "1.28.0" ;;
    esac
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
