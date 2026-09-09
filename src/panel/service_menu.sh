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
