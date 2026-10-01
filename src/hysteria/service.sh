# shellcheck shell=bash
# 职责: Hysteria2 服务状态变更；菜单交互位于 panel/service_menu.sh

restart_hy2_service_checked() {
    systemctl restart "${HY2_SERVICE}" || return 1
    # Type=simple 的 restart 成功不代表进程未随后退出；与现有配置流程观察窗口一致。
    sleep 2
    systemctl is-active --quiet "${HY2_SERVICE}"
}

change_hy2_service_state() {
    local action="$1"
    case "${action}" in
        start|stop|restart) systemctl "${action}" "${HY2_SERVICE}" ;;
        *) err "不支持的服务操作: ${action}"; return 1 ;;
    esac
}
