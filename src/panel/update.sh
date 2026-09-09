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
