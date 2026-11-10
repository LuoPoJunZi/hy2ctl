# shellcheck shell=bash
# 职责: 只读收集 Linux 内核与 MPTCP 证据；不以通用版本号推断厂商补丁状态。

is_valid_linux_kernel_release() {
    [[ ${#1} -le 128 && "$1" =~ ^[0-9][a-zA-Z0-9._+~-]*$ ]]
}

get_running_kernel_package() {
    local kernel_release="$1" package package_output package_version
    is_valid_linux_kernel_release "${kernel_release}" || return 1
    if command -v dpkg-query >/dev/null 2>&1; then
        # 只查询 uname -r 对应的已安装映像，不能用“最新已安装内核”冒充正在运行的内核。
        for package in "linux-image-${kernel_release}" "linux-image-unsigned-${kernel_release}"; do
            package_output="$(dpkg-query -W -f='${db:Status-Status} ${Package} ${Version}' "${package}" 2>/dev/null)" || continue
            if [[ "${package_output}" =~ ^installed[[:blank:]]+([^[:space:]]+)[[:blank:]]+([0-9][a-zA-Z0-9.+:~_-]*)$ && "${BASH_REMATCH[1]}" == "${package}" ]]; then
                package_version="${BASH_REMATCH[2]}"
                printf '%s %s\n' "${package}" "${package_version}"
                return 0
            fi
        done
    elif command -v rpm >/dev/null 2>&1; then
        package_output="$(rpm -qf --qf '%{NAME} %{VERSION}-%{RELEASE}' "/boot/vmlinuz-${kernel_release}" 2>/dev/null)" || return 1
        if [[ "${package_output}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*[[:blank:]]+[0-9][a-zA-Z0-9.+:~_-]*$ ]]; then
            printf '%s\n' "${package_output}"
            return 0
        fi
    fi
    return 1
}

get_linux_mptcp_state() {
    local state_file="${HY2_MPTCP_ENABLED_FILE:-/proc/sys/net/mptcp/enabled}" state
    [[ -f "${state_file}" && -r "${state_file}" ]] || return 1
    state="$(cat -- "${state_file}" 2>/dev/null)" || return 1
    case "${state}" in
        0|1) printf '%s\n' "${state}" ;;
        *) return 1 ;;
    esac
}

diagnostic_check_kernel_security() {
    local system kernel_release os_id os_version package_info mptcp_state command_hint
    if ! system="$(uname -s 2>/dev/null)" || [[ "${system}" != Linux ]]; then
        diagnostic_print_result "WARN" "当前环境非 Linux 或系统类型未知，无法核验 CVE-2026-98432 系统内核修复状态。"
        diagnostic_add_item \
            "系统内核安全状态未知。" \
            "请在实际 Linux VPS 上核对运行内核与发行版安全公告。" \
            "uname -s && uname -r"
        return 0
    fi

    os_id="$(diagnostic_os_release_field ID)" || os_id=unknown
    os_version="$(diagnostic_os_release_field VERSION_ID)" || os_version=unknown
    if kernel_release="$(uname -r 2>/dev/null)" && is_valid_linux_kernel_release "${kernel_release}"; then
        diagnostic_print_result "WARN" "运行中的 Linux 内核: ${kernel_release}（${os_id} ${os_version}）；CVE-2026-98432 修复状态需按发行版公告核验。"
        package_info="$(get_running_kernel_package "${kernel_release}")" || package_info="运行内核包未知（工具缺失、容器或自编译内核等需人工核对）"
    else
        diagnostic_print_result "WARN" "运行中的 Linux 内核版本未知（${os_id} ${os_version}）；无法确认 CVE-2026-98432 修复状态。"
        package_info="运行内核包未知"
    fi
    printf '  对应运行内核包: %s\n' "${package_info}"
    diagnostic_log "running_kernel_package=${package_info}"

    if ! mptcp_state="$(get_linux_mptcp_state)"; then
        diagnostic_print_result "WARN" "MPTCP 状态未知（接口缺失、不可读或内容异常）；不能据此判定系统内核已修复。"
    elif [[ "${mptcp_state}" == 0 ]]; then
        diagnostic_print_result "WARN" "内核 MPTCP 开关: 0（已关闭）；关闭 MPTCP 不等于修复 CVE-2026-98432，普通 IPv4 TCP 仍需核验。"
    else
        diagnostic_print_result "WARN" "内核 MPTCP 开关: 1（已启用）；不代表存在实际 MPTCP 监听，需核对 IPv4 TCP 服务与系统内核补丁。"
    fi

    command_hint="uname -r；按 ${os_id} 官方公告核对 CVE-2026-98432 与实际内核分支"
    if [[ "${os_id}" == ubuntu ]]; then
        command_hint="uname -r；Ubuntu 公告 https://ubuntu.com/security/CVE-2026-98432（generic / oracle 等分支分别核验）"
    fi
    diagnostic_add_item \
        "Linux IPv4 TCP 系统内核补丁需要人工核验。" \
        "按发行版及内核分支核对正式安全更新，安装修复后重启并复查正在运行的内核；仅已安装新包不代表补丁已生效。关闭 MPTCP 仅缓解风险，不能代替系统内核补丁。不自动启用 -proposed 源或修改防火墙；菜单 (11) 不更新 Linux 系统内核。" \
        "${command_hint}"
}
