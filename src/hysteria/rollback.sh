# shellcheck shell=bash
# 职责: 配置失败回滚与启动故障提示

abort_pending_config_change() {
    local reason="$1"
    if restore_runtime_files; then
        err "${reason}，已恢复变更前文件。"
    else
        err "${reason}，且自动恢复失败，请立即检查 ${HY2_CONF_DIR}。"
    fi
}

restart_service_with_rollback() {
    if restart_hy2_service_checked; then
        return 0
    fi
    err "重启服务失败或服务未保持运行，正在尝试自动回滚到上一版配置..."
    show_service_failure_hint
    if restore_runtime_files && restart_hy2_service_checked; then
        err "已回滚到上一版配置，本次变更未生效。"
    else
        err "自动回滚失败，请手动检查 ${HY2_CONF_FILE} 和服务日志。"
    fi
    show_recent_service_logs
    return 1
}

show_recent_service_logs() {
    print_line
    echo -e "${_yellow}[提示]${_plain} 最近 20 行服务日志："
    journalctl -u "${HY2_SERVICE}" --no-pager -n 20 2>/dev/null || true
    print_line
}

show_service_failure_hint() {
    local logs
    logs="$(journalctl -u "${HY2_SERVICE}" --no-pager -n 60 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    [[ -z "${logs}" ]] && return 0

    if [[ "${logs}" == *"permission denied"* && "${logs}" == *"config.yaml"* ]]; then
        err "诊断结论：服务用户无权读取 config.yaml。"
        echo -e "      建议执行：systemctl show -p User,Group ${HY2_SERVICE}"
        echo -e "      建议执行：namei -l ${HY2_CONF_FILE}"
        return 0
    fi
    if [[ "${logs}" == *"address already in use"* || "${logs}" == *"bind: address already in use"* ]]; then
        err "诊断结论：监听端口被占用。"
        echo -e "      建议执行：ss -lntp | grep \":${port:-443}\\b\""
        return 0
    fi
    if [[ "${logs}" == *"acme"* && ( "${logs}" == *"timeout"* || "${logs}" == *"no such host"* || "${logs}" == *"dns"* ) ]]; then
        err "诊断结论：CA 证书申请失败（可能是 DNS/80/443 不通）。"
        echo -e "      建议检查：域名 A/AAAA 解析、80/443 入站、防火墙与云安全组。"
        return 0
    fi
    if [[ "${logs}" == *"failed to read server config"* || "${logs}" == *"yaml"* || "${logs}" == *"parse"* ]]; then
        err "诊断结论：配置文件内容异常或格式错误。"
        echo -e "      建议执行：hysteria server -c ${HY2_CONF_FILE}"
        return 0
    fi
}
