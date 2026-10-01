# shellcheck shell=bash
# 职责: 校验并恢复最近的 Hysteria2 手动备份

find_latest_manual_backup() {
    ls -1dt "${HY2_BACKUP_DIR}"/manual-* 2>/dev/null | head -n 1 || true
}

validate_manual_backup_dir() {
    local backup_dir="$1"

    if [[ -z "${backup_dir}" || ! -d "${backup_dir}" ]]; then
        err "未找到可恢复的手动备份。"
        return 1
    fi
    if [[ ! -f "${backup_dir}/config.yaml" ]]; then
        err "备份中缺少 config.yaml，已中止恢复: ${backup_dir}"
        return 1
    fi
    if grep -q '^tls:' "${backup_dir}/config.yaml" && \
        [[ ! -f "${backup_dir}/server.crt" || ! -f "${backup_dir}/server.key" ]]; then
        err "自签模式备份缺少证书或私钥，已中止恢复: ${backup_dir}"
        return 1
    fi
}

restore_manual_backup_files() {
    local backup_dir="$1"
    local backup_uses_tls="$2"
    local restore_failed=0

    cp -p -- "${backup_dir}/config.yaml" "${HY2_CONF_FILE}" || restore_failed=1
    if [[ -f "${backup_dir}/meta.info" ]]; then
        cp -p -- "${backup_dir}/meta.info" "${HY2_META_FILE}" || restore_failed=1
    else
        rm -f -- "${HY2_META_FILE}" || restore_failed=1
    fi
    if [[ "${backup_uses_tls}" -eq 1 ]]; then
        cp -p -- "${backup_dir}/server.crt" "${HY2_CONF_DIR}/server.crt" || restore_failed=1
        cp -p -- "${backup_dir}/server.key" "${HY2_CONF_DIR}/server.key" || restore_failed=1
    else
        rm -f -- "${HY2_CONF_DIR}/server.crt" "${HY2_CONF_DIR}/server.key" || restore_failed=1
    fi

    [[ "${restore_failed}" -eq 0 ]]
}

set_manual_restore_permissions() {
    local backup_uses_tls="$1"

    set_config_dir_permissions
    set_server_config_permissions
    if [[ -f "${HY2_META_FILE}" ]]; then
        chmod 600 "${HY2_META_FILE}" 2>/dev/null || true
    fi
    if [[ "${backup_uses_tls}" -eq 1 ]]; then
        set_tls_file_permissions
    fi
}

restore_latest_manual_backup() {
    local latest_dir
    local backup_uses_tls=0

    latest_dir="$(find_latest_manual_backup)"
    if ! validate_manual_backup_dir "${latest_dir}"; then
        return 1
    fi
    if grep -q '^tls:' "${latest_dir}/config.yaml"; then
        backup_uses_tls=1
    fi

    if ! backup_runtime_files; then
        err "无法备份当前运行配置，已中止恢复操作。"
        return 1
    fi

    if ! restore_manual_backup_files "${latest_dir}" "${backup_uses_tls}"; then
        if restore_runtime_files; then
            err "恢复备份文件失败，已恢复操作前配置。"
        else
            err "恢复备份文件失败，且无法恢复操作前配置，请立即检查 ${HY2_CONF_DIR}。"
        fi
        return 1
    fi

    set_manual_restore_permissions "${backup_uses_tls}"

    if restart_hy2_service_checked >/dev/null 2>&1; then
        ok "已恢复最近备份并重启服务: ${latest_dir}"
        return 0
    fi

    err "备份文件已恢复，但服务重启失败或未保持运行，正在回滚到操作前配置..."
    show_service_failure_hint
    if restore_runtime_files && restart_hy2_service_checked >/dev/null 2>&1; then
        err "已恢复操作前配置，本次手动恢复未生效。"
    else
        err "自动回滚失败，请立即检查配置与服务日志。"
    fi
    show_recent_service_logs
    return 1
}
