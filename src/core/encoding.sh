# shellcheck shell=bash
# 职责: YAML、URL、JSON 与主机地址编码

yaml_single_quote() {
    local raw="$1"
    local escaped="${raw//\'/\'\'}"
    printf "'%s'" "${escaped}"
}

url_encode() {
    local raw="$1"
    local LC_ALL=C
    local length="${#raw}"
    local i char out=""
    for (( i = 0; i < length; i++ )); do
        char="${raw:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) out+="${char}" ;;
            *) printf -v out '%s%%%02X' "${out}" "'${char}" ;;
        esac
    done
    printf '%s' "${out}"
}

json_escape() {
    local s="$1"
    local code char escaped
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    # 常见字符串保留快速路径；其余 U+0001..U+001F 也必须转义为合法 JSON。
    # Bash 字符串无法保存 NUL，因此不接受/不宣称支持 U+0000 输入。
    if [[ "${s}" == *[$'\001'-$'\037']* ]]; then
        for ((code = 1; code < 32; code++)); do
            printf -v escaped '\\u%04x' "${code}"
            printf -v char '%b' "${escaped}"
            s="${s//"${char}"/"${escaped}"}"
        done
    fi
    printf '%s' "${s}"
}

format_host_for_url() {
    local host="$1"
    if [[ "${host}" == *:* ]]; then
        printf '[%s]' "${host}"
        return
    fi
    printf '%s' "${host}"
}
