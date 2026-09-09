# shellcheck shell=bash
# 职责: 通用文件原子写入

write_file_atomic() {
    local target="$1"
    local tmp_file
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")" || return 1
    if ! cat > "${tmp_file}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    if ! mv -f "${tmp_file}" "${target}"; then
        rm -f "${tmp_file}" >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}
