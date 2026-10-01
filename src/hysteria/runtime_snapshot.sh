# shellcheck shell=bash
# 职责: Hysteria2 四文件自动快照、缺失状态与恢复后的权限收敛

get_runtime_snapshot_dir() {
    local pointer="${HY2_BACKUP_DIR}/runtime.current"
    local snapshot_name
    if [[ -e "${pointer}" || -L "${pointer}" ]]; then
        [[ -f "${pointer}" && ! -L "${pointer}" ]] || return 1
        snapshot_name="$(<"${pointer}")" || return 1
        [[ "${snapshot_name}" =~ ^runtime-[A-Za-z0-9]{6}$ ]] || return 1
        [[ -d "${HY2_BACKUP_DIR}/${snapshot_name}" && ! -L "${HY2_BACKUP_DIR}/${snapshot_name}" ]] || return 1
        printf '%s\n' "${HY2_BACKUP_DIR}/${snapshot_name}"
    else
        # 升级后仍可恢复旧版平铺的 .bak / .bak.absent 快照。
        printf '%s\n' "${HY2_BACKUP_DIR}"
    fi
}

validate_runtime_snapshot_dir() {
    local snapshot_dir="$1"
    local name backup_file absent_marker
    [[ -d "${snapshot_dir}" && ! -L "${snapshot_dir}" ]] || return 1
    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        backup_file="${snapshot_dir}/${name}.bak"
        absent_marker="${backup_file}.absent"
        [[ ! -L "${backup_file}" && ! -L "${absent_marker}" ]] || return 1
        if [[ -f "${backup_file}" && ! -e "${absent_marker}" ]]; then
            continue
        elif [[ -f "${absent_marker}" && ! -e "${backup_file}" ]]; then
            continue
        else
            return 1
        fi
    done
}

discard_runtime_snapshot() {
    local snapshot_dir="$1" name
    local -a files=()
    # 仅清理本模块创建的直接子目录及八个已知文件，不递归删除备份根目录。
    [[ "${snapshot_dir%/*}" == "${HY2_BACKUP_DIR}" && "${snapshot_dir##*/}" =~ ^runtime-[A-Za-z0-9]{6}$ ]] || return 1
    [[ -d "${snapshot_dir}" && ! -L "${snapshot_dir}" ]] || return 1
    if [[ -f "${HY2_BACKUP_DIR}/runtime.current" && "$(<"${HY2_BACKUP_DIR}/runtime.current")" == "${snapshot_dir##*/}" ]]; then
        return 1
    fi
    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        files+=("${snapshot_dir}/${name}.bak" "${snapshot_dir}/${name}.bak.absent")
    done
    rm -f -- "${files[@]}" && rm -d -- "${snapshot_dir}"
}

backup_runtime_files() {
    local name source_file backup_file snapshot_dir previous_dir
    local snapshot_failed=0
    mkdir -p "${HY2_BACKUP_DIR}" || return 1
    previous_dir="$(get_runtime_snapshot_dir)" || return 1
    snapshot_dir="$(mktemp -d "${HY2_BACKUP_DIR}/runtime-XXXXXX")" || return 1

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        source_file="${HY2_CONF_DIR}/${name}"
        backup_file="${snapshot_dir}/${name}.bak"
        if [[ -f "${source_file}" ]]; then
            cp -p -- "${source_file}" "${backup_file}" || snapshot_failed=1
        elif [[ ! -e "${source_file}" && ! -L "${source_file}" ]]; then
            : > "${backup_file}.absent" || snapshot_failed=1
        else
            snapshot_failed=1
        fi
        (( snapshot_failed == 0 )) || break
    done

    if (( snapshot_failed != 0 )) || ! validate_runtime_snapshot_dir "${snapshot_dir}" || \
        ! write_file_atomic "${HY2_BACKUP_DIR}/runtime.current" <<< "${snapshot_dir##*/}"; then
        discard_runtime_snapshot "${snapshot_dir}" >/dev/null 2>&1 || true
        return 1
    fi
    # 只有完整新快照发布成功才清理旧的新版快照；旧版平铺文件和手动备份不动。
    if [[ "${previous_dir}" != "${HY2_BACKUP_DIR}" ]]; then
        discard_runtime_snapshot "${previous_dir}" >/dev/null 2>&1 || true
    fi
    return 0
}

restore_runtime_files() {
    local name target_file backup_file absent_marker snapshot_dir
    local restore_failed=0
    snapshot_dir="$(get_runtime_snapshot_dir)" || return 1
    # 四项状态必须完整且互斥；不能恢复到一半才发现快照损坏。
    validate_runtime_snapshot_dir "${snapshot_dir}" || return 1

    for name in "${RUNTIME_FILE_NAMES[@]}"; do
        target_file="${HY2_CONF_DIR}/${name}"
        backup_file="${snapshot_dir}/${name}.bak"
        absent_marker="${backup_file}.absent"
        if [[ -f "${backup_file}" ]]; then
            cp -p -- "${backup_file}" "${target_file}" || restore_failed=1
        elif [[ -f "${absent_marker}" ]]; then
            rm -f -- "${target_file}" || restore_failed=1
        else
            restore_failed=1
        fi
    done

    if [[ "${restore_failed}" -ne 0 ]]; then
        return 1
    fi

    set_config_dir_permissions
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        set_server_config_permissions
    fi
    if [[ -f "${HY2_META_FILE}" ]]; then
        chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true
    fi
    if [[ -f "${HY2_CONF_DIR}/server.key" && -f "${HY2_CONF_DIR}/server.crt" ]]; then
        set_tls_file_permissions
    fi
    return 0
}
