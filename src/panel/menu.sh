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
