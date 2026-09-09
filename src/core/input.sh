# shellcheck shell=bash
# 职责: 交互输入边界；空行允许采用默认值，EOF 必须中止当前操作

read_input() {
    if ! read -r -p "$1" "$2"; then
        err "输入已结束，取消当前操作。" >&2
        return 1
    fi
}
