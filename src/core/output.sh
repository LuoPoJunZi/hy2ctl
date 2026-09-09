# shellcheck shell=bash
# 职责: 终端消息与基础界面输出

msg() { printf '%b[信息]%b %s\n' "${_blue}" "${_plain}" "$1"; }

ok() { printf '%b[成功]%b %s\n' "${_green}" "${_plain}" "$1"; }

err() { printf '%b[错误]%b %s\n' "${_red}" "${_plain}" "$1"; }

print_line() { echo -e "${_blue}=====================================================${_plain}"; }

print_sub_line() { echo -e "${_blue}-----------------------------------------------------${_plain}"; }

wait_return() { read -n 1 -s -r -p "按任意键返回主菜单..."; }
