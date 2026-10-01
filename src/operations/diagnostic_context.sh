# shellcheck shell=bash
# 职责: 诊断上下文、计数与建议去重

diagnostic_reset_context() {
    DIAG_OK_COUNT=0
    DIAG_WARN_COUNT=0
    DIAG_FAIL_COUNT=0
    DIAG_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    DIAG_CONCLUSIONS=()
    DIAG_SUGGESTIONS=()
    DIAG_COMMANDS=()
    # 独占创建并使用 600 权限，避免同秒覆盖和 /tmp 预置符号链接。
    DIAG_FILE="$(mktemp "${HY2_DIAG_DIR}/hy2-diagnose-${DIAG_TIMESTAMP}.XXXXXX.log" 2>/dev/null)" || DIAG_FILE=""
}

diagnostic_log() {
    local text="$1"
    if [[ -n "${DIAG_FILE}" ]]; then
        echo -e "${text}" >> "${DIAG_FILE}"
    fi
}

diagnostic_print_result() {
    local level="$1"
    local text="$2"
    case "${level}" in
        OK)
            echo -e "${_green}[OK]${_plain} ${text}"
            diagnostic_log "[OK] ${text}"
            DIAG_OK_COUNT=$((DIAG_OK_COUNT + 1))
            ;;
        WARN)
            echo -e "${_yellow}[WARN]${_plain} ${text}"
            diagnostic_log "[WARN] ${text}"
            DIAG_WARN_COUNT=$((DIAG_WARN_COUNT + 1))
            ;;
        FAIL)
            echo -e "${_red}[FAIL]${_plain} ${text}"
            diagnostic_log "[FAIL] ${text}"
            DIAG_FAIL_COUNT=$((DIAG_FAIL_COUNT + 1))
            ;;
    esac
}

diagnostic_add_item() {
    local conclusion="$1"
    local suggestion="$2"
    local command_hint="$3"
    local existing
    for existing in "${DIAG_CONCLUSIONS[@]}"; do
        if [[ "${existing}" == "${conclusion}" ]]; then
            return 0
        fi
    done
    DIAG_CONCLUSIONS+=("${conclusion}")
    DIAG_SUGGESTIONS+=("${suggestion}")
    DIAG_COMMANDS+=("${command_hint}")
}
