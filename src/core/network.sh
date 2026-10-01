# shellcheck shell=bash
# 职责: 有界脚本下载与服务器公网地址发现

# target 由调用方通过 mktemp 创建；失败后的删除、校验与替换仍由调用方负责。
download_script() {
    curl -fL --retry 2 --connect-timeout 8 --max-time 120 \
        -o "$2" "$1" >/dev/null 2>&1
}

fetch_public_ip() {
    local candidate family url
    local LC_ALL=C
    for family in 4 6; do
        if [[ "${family}" == 4 ]]; then url='https://api.ipify.org'; else url='https://api64.ipify.org'; fi
        if candidate="$(curl -fsS"${family}" --connect-timeout 3 --max-time 6 --max-filesize 128 "${url}" 2>/dev/null)"; then
            # 旧版 curl 对未知长度响应不执行 max-filesize，结果仍必须受长度约束。
            (( ${#candidate} <= 128 )) || continue
            # 允许服务响应末尾换行/CRLF，不接受多行或嵌入字段。
            candidate="${candidate#"${candidate%%[![:space:]]*}"}"
            candidate="${candidate%"${candidate##*[![:space:]]}"}"
            if is_public_ip "${candidate}"; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        fi
    done
    return 1
}

fetch_local_ip() {
    local addresses candidate fallback=""
    local -a candidates=()
    addresses="$(hostname -I 2>/dev/null)" || return 1
    read -r -a candidates <<< "${addresses}"
    for candidate in "${candidates[@]}"; do
        is_valid_ip "${candidate}" || continue
        if is_public_ip "${candidate}"; then
            printf '%s\n' "${candidate}"
            return 0
        fi
        [[ -n "${fallback}" ]] || fallback="${candidate}"
    done
    [[ -n "${fallback}" ]] || return 1
    printf '%s\n' "${fallback}"
}

fetch_server_ip() {
    fetch_public_ip || fetch_local_ip
}
