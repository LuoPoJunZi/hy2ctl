# shellcheck shell=bash
# 工程共享接口：仅解析纯文本清单，不执行清单内容；不进入 VPS 单文件。

load_panel_modules() {
    local root="$1" module discovered listed
    local manifest="${root}/scripts/panel-modules.list"
    MODULES=()
    MODULE_PATHS=()
    [[ -r "${manifest}" ]] || { echo "[ERROR] Missing module manifest: ${manifest}" >&2; return 1; }
    while IFS= read -r module || [[ -n "${module}" ]]; do
        [[ -z "${module}" || "${module}" == \#* ]] && continue
        if [[ ! "${module}" =~ ^src/([a-zA-Z0-9_-]+/)*[a-zA-Z0-9_-]+\.sh$ ]]; then
            echo "[ERROR] Invalid module path: ${module}" >&2
            return 1
        fi
        [[ -s "${root}/${module}" ]] || { echo "[ERROR] Missing source module: ${module}" >&2; return 1; }
        MODULES+=("${module}")
        MODULE_PATHS+=("${root}/${module}")
    done < "${manifest}"
    [[ "${#MODULES[@]}" -ge 2 ]] || return 1
    if [[ "${MODULES[0]}" != src/bootstrap.sh || "${MODULES[${#MODULES[@]}-1]}" != src/main.sh ]]; then
        echo "[ERROR] Manifest must start with bootstrap.sh and end with main.sh" >&2
        return 1
    fi
    discovered="$(cd "${root}" && find src -type f -name '*.sh' -print | LC_ALL=C sort)" || return 1
    listed="$(printf '%s\n' "${MODULES[@]}" | LC_ALL=C sort)" || return 1
    if [[ "${discovered}" != "${listed}" ]]; then
        echo "[ERROR] Source manifest has missing, duplicate or unlisted modules" >&2
        return 1
    fi
}
