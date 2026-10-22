# shellcheck shell=bash
# 职责: 本机 Go 构建与系统 CA 包的只读核验；不更新软件包、不访问网络。

diagnostic_check_go_trust() {
    local go_version
    command -v hysteria >/dev/null 2>&1 || return 0
    if ! go_version="$(get_hy2_go_version)"; then
        diagnostic_print_result "WARN" "Hysteria2 Go 构建版本未知，无法确认 CVE-2026-111943 工具链修复状态。"
    elif go_version_has_ca_mitigation "${go_version}"; then
        diagnostic_print_result "OK" "Hysteria2 Go 构建版本: ${go_version}，达到 CVE-2026-111943 工具链基线（不代表系统 CA 已更新）。"
        return 0
    else
        diagnostic_print_result "WARN" "Hysteria2 Go 构建版本: ${go_version}，未达到 CVE-2026-111943 工具链基线；厂商回移修复需另行确认。"
    fi
    diagnostic_add_item \
        "Hysteria2 的 Go 证书验证修复需要核对。" \
        "向内核上游核对 Go 1.26.10 / 1.27.3 或后续修复构建；仅升级系统 Go 不会修复现有二进制。系统 CA 更新也需单独检查，不关闭 TLS 校验。" \
        "hysteria version；公告 https://go.dev/issue/82345；菜单 (11) 检查官方内核更新"
}

diagnostic_os_release_field() {
    local wanted="$1" key value
    local release_file="${HY2_OS_RELEASE_FILE:-/etc/os-release}"
    [[ -f "${release_file}" && -r "${release_file}" ]] || return 1
    # 不 source / eval 系统描述文件，且只返回诊断需要的简单值。
    while IFS='=' read -r key value || [[ -n "${key}" ]]; do
        [[ "${key}" == "${wanted}" ]] || continue
        case "${value}" in
            \"*\") value="${value:1:${#value}-2}" ;;
            \'*\') value="${value:1:${#value}-2}" ;;
        esac
        [[ "${value}" =~ ^[a-zA-Z0-9._-]+$ ]] || return 1
        printf '%s\n' "${value}"
        return 0
    done < "${release_file}"
    return 1
}

get_ca_certificates_version() {
    local package_output package_version
    if command -v dpkg-query >/dev/null 2>&1; then
        package_output="$(dpkg-query -W -f='${db:Status-Status} ${Version}' ca-certificates 2>/dev/null)" || return 1
        [[ "${package_output}" =~ ^installed[[:blank:]]+([0-9][a-zA-Z0-9.+:~_-]*)$ ]] || return 1
        package_version="${BASH_REMATCH[1]}"
    elif command -v rpm >/dev/null 2>&1; then
        package_version="$(rpm -q --qf '%{VERSION}-%{RELEASE}' ca-certificates 2>/dev/null)" || return 1
    else
        return 1
    fi
    [[ "${package_version}" =~ ^[0-9][a-zA-Z0-9.+:~_-]*$ ]] || return 1
    printf '%s\n' "${package_version}"
}

diagnostic_check_ca_trust() {
    local os_id os_version ca_version baseline="" compare_status
    local update_hint="按发行版官方安全公告手动更新 ca-certificates；不要绕过 TLS 验证。"
    local command_hint="cat /etc/os-release；核对发行版 ca-certificates 安全公告"
    os_id="$(diagnostic_os_release_field ID)" || os_id="unknown"
    os_version="$(diagnostic_os_release_field VERSION_ID)" || os_version="unknown"
    if [[ "${os_id}" == "ubuntu" ]]; then
        # USN-8944-1（2026-10-20），不同发行版不可复用此包版本基线。
        case "${os_version}" in
            22.04|24.04|26.04|26.10) baseline="20260816ubuntu0.${os_version}.1" ;;
        esac
        command_hint="apt-get update && apt-get install --only-upgrade ca-certificates"
    fi

    if ! ca_version="$(get_ca_certificates_version)"; then
        if [[ "${os_id}" == "ubuntu" ]]; then
            command_hint="apt-get update && apt-get install ca-certificates"
        fi
        diagnostic_print_result "WARN" "系统 ca-certificates 未安装或版本不可读，证书信任库状态未知（${os_id} ${os_version}）。"
    elif [[ -z "${baseline}" ]] || ! command -v dpkg >/dev/null 2>&1; then
        diagnostic_print_result "WARN" "系统 ca-certificates: ${ca_version}（${os_id} ${os_version}）；无可用的发行版核验基线或比较工具，修复状态未知。"
    elif dpkg --compare-versions "${ca_version}" ge "${baseline}"; then
        diagnostic_print_result "OK" "Ubuntu ${os_version} ca-certificates: ${ca_version}，达到 USN-8944-1 软件包基线（自定义/内置 CA 库未核验）。"
        return 0
    else
        compare_status=$?
        if [[ "${compare_status}" -eq 1 ]]; then
            diagnostic_print_result "WARN" "Ubuntu ${os_version} ca-certificates: ${ca_version}，低于 USN-8944-1 修复版本 ${baseline}。"
        else
            diagnostic_print_result "WARN" "系统 ca-certificates: ${ca_version}；软件包版本比较失败，修复状态未知。"
        fi
    fi
    diagnostic_add_item \
        "系统 CA 信任库需要人工核对。" \
        "${update_hint} Ubuntu 参考 https://ubuntu.com/security/notices/USN-8944-1；包版本检查不涵盖自定义/内置 CA 库。更新后按发行版说明重启使用旧信任库的进程。" \
        "${command_hint}"
}
