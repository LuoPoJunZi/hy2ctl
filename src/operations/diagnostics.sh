# shellcheck shell=bash
# 职责: 环境诊断与报告查看

show_diagnostics() {
    diagnostic_reset_context

    clear
    print_line
    echo -e "             ${_green}--- 一键环境诊断 ---${_plain}"
    print_line
    if [[ -n "${DIAG_FILE}" ]]; then
        diagnostic_log "=== hy2ctl Diagnose @ ${DIAG_TIMESTAMP} ==="
        diagnostic_log "config_file=${HY2_CONF_FILE}"
        diagnostic_log "meta_file=${HY2_META_FILE}"
        diagnostic_log "service=${HY2_SERVICE}"
    fi

    diagnostic_check_core

    diagnostic_check_go_trust

    diagnostic_check_ca_trust

    diagnostic_check_service

    diagnostic_check_runtime_files

    diagnostic_check_server_config

    diagnostic_check_public_ip

    diagnostic_render_summary
    wait_return
}

show_latest_diagnostics_report() {
    clear
    print_line
    echo -e "            ${_green}--- 最近诊断报告 ---${_plain}"
    print_line
    if [[ ! -f "${HY2_DIAG_LATEST}" ]]; then
        err "未找到最近诊断报告。请先执行菜单 (8) 一键环境诊断。"
        print_line
        wait_return
        return
    fi
    cat "${HY2_DIAG_LATEST}"
    print_line
    wait_return
}
