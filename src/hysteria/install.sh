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
