# shellcheck shell=bash
# 职责: Hysteria2 服务状态变更；菜单交互位于 panel/service_menu.sh

change_hy2_service_state() {
    local action="$1"
    case "${action}" in
        start|stop|restart) systemctl "${action}" "${HY2_SERVICE}" ;;
        *) err "不支持的服务操作: ${action}"; return 1 ;;
    esac
}
