# shellcheck shell=bash
# 职责: 手动备份与恢复菜单编排

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
