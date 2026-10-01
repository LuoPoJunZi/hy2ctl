# shellcheck shell=bash
# 职责: 诊断结果摘要、建议与报告导出

diagnostic_render_summary() {
    local line_status summary_plain idx

    print_line
    if (( DIAG_FAIL_COUNT > 0 )); then
        line_status="${_red}诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / ${DIAG_FAIL_COUNT} FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / ${DIAG_FAIL_COUNT} FAIL"
    elif (( DIAG_WARN_COUNT > 0 )); then
        line_status="${_yellow}诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / ${DIAG_WARN_COUNT} WARN / 0 FAIL"
    else
        line_status="${_green}诊断结果: ${DIAG_OK_COUNT} OK / 0 WARN / 0 FAIL${_plain}"
        summary_plain="诊断结果: ${DIAG_OK_COUNT} OK / 0 WARN / 0 FAIL"
    fi
    echo -e "${line_status}"
    diagnostic_log "${summary_plain}"
    echo -e "${_blue}[分级]${_plain} 阻断项(FAIL): ${DIAG_FAIL_COUNT} | 警告项(WARN): ${DIAG_WARN_COUNT} | 建议项: ${#DIAG_CONCLUSIONS[@]}"
    diagnostic_log "分级: 阻断项(FAIL)=${DIAG_FAIL_COUNT}, 警告项(WARN)=${DIAG_WARN_COUNT}, 建议项=${#DIAG_CONCLUSIONS[@]}"
    if (( ${#DIAG_CONCLUSIONS[@]} > 0 )); then
        print_line
        echo -e "${_yellow}[诊断建议]${_plain} 结论 + 建议 + 命令"
        diagnostic_log "--- 诊断建议 ---"
        for idx in "${!DIAG_CONCLUSIONS[@]}"; do
            echo -e "  [结论] ${DIAG_CONCLUSIONS[${idx}]}"
            echo -e "  [建议] ${DIAG_SUGGESTIONS[${idx}]}"
            echo -e "  [命令] ${DIAG_COMMANDS[${idx}]}"
            echo -e ""
            diagnostic_log "[结论] ${DIAG_CONCLUSIONS[${idx}]}"
            diagnostic_log "[建议] ${DIAG_SUGGESTIONS[${idx}]}"
            diagnostic_log "[命令] ${DIAG_COMMANDS[${idx}]}"
            diagnostic_log ""
        done
    fi
    if [[ -n "${DIAG_FILE}" ]]; then
        echo -e "${_blue}[信息]${_plain} 诊断报告已导出: ${DIAG_FILE}"
        if write_file_atomic "${HY2_DIAG_LATEST}" < "${DIAG_FILE}" 2>/dev/null; then
            echo -e "${_blue}[信息]${_plain} 最新报告快捷路径: ${HY2_DIAG_LATEST}"
        else
            echo -e "${_yellow}[提示]${_plain} 最新报告快捷路径更新失败，请使用上方报告路径。"
        fi
    else
        echo -e "${_yellow}[提示]${_plain} 诊断报告导出失败，仅显示终端结果。"
    fi
    print_line
}
