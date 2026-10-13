#!/bin/bash
# ==========================================
# 项目: hy2ctl 安装与更新引导脚本
# 描述: 下载并部署管理面板到系统级命令
# ==========================================

# source 仅加载函数供无特权测试使用，不修改调用者的 Shell 选项。
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    set -euo pipefail
fi

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_plain="\033[0m"

# GitHub 官方仓库 Raw 地址前缀
GITHUB_RAW_URL="https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main"
TARGET_BIN="/usr/local/bin/hy2"

msg() { echo -e "${_yellow}[信息]${_plain} $1"; }
ok() { echo -e "${_green}[成功]${_plain} $1"; }
err() { echo -e "${_red}[错误]${_plain} $1"; }

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "缺少依赖命令: ${cmd}"
        return 1
    fi
    return 0
}

preflight_check() {
    local missing=0
    local cmd
    for cmd in bash grep head mktemp chmod mkdir mv rm; do
        if ! require_cmd "${cmd}"; then
            missing=1
        fi
    done
    if [[ "${missing}" -ne 0 ]]; then
        err "安装器运行环境不完整，请先补齐依赖命令后重试。"
        exit 1
    fi
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "请使用 root 用户运行此脚本！"
        exit 1
    fi
}

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
        return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
        return 0
    fi
    if command -v yum >/dev/null 2>&1; then
        echo "yum"
        return 0
    fi
    return 1
}

install_dependencies() {
    local pm="$1" cmd
    local -a missing_commands=()
    local -a apt_options=(
        -o DPkg::Lock::Timeout=60
        -o Acquire::Retries=2
        -o Acquire::http::Timeout=20
        -o Acquire::https::Timeout=20
    )
    msg "正在检查基础依赖 (curl, openssl；wget 为可选下载回退)..."
    for cmd in curl openssl; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing_commands+=("${cmd}")
        fi
    done
    if [[ "${#missing_commands[@]}" -eq 0 ]]; then
        msg "基础依赖已齐全，跳过软件包索引刷新与安装。"
        return 0
    fi

    msg "仅安装缺失依赖: ${missing_commands[*]}"
    case "${pm}" in
        apt-get)
            # 保留原始错误；不绕过签名验证，不删除包管理器锁或改写软件源。
            if ! apt-get "${apt_options[@]}" update; then
                err "APT 软件包索引刷新失败，请根据上方错误检查软件源、网络或索引锁占用。"
                return 1
            fi
            if ! DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y "${missing_commands[@]}"; then
                err "APT 依赖安装失败，请根据上方错误检查 dpkg 锁占用或软件包状态。"
                return 1
            fi
            ;;
        dnf|yum)
            if ! "${pm}" install -y "${missing_commands[@]}"; then
                err "${pm} 依赖安装失败，请根据上方错误检查软件源或软件包状态。"
                return 1
            fi
            ;;
        *)
            err "不支持的包管理器: ${pm}"
            return 1
            ;;
    esac
    for cmd in curl openssl; do
        require_cmd "${cmd}" || return 1
    done
    return 0
}

verify_downloaded_panel() {
    local file="$1"
    if [[ ! -s "${file}" ]]; then
        return 1
    fi
    if ! head -n 1 "${file}" | grep -q '^#!/bin/bash'; then
        return 1
    fi
    if ! grep -q 'main_menu' "${file}"; then
        return 1
    fi
    if ! grep -q 'hy2ctl 管理面板' "${file}"; then
        return 1
    fi
    if ! grep -q -- '--install-core) install_hy2_core' "${file}"; then
        return 1
    fi
    if ! grep -Eq '^sh_ver="v[0-9]+\.[0-9]+\.[0-9]+"' "${file}"; then
        return 1
    fi
    if ! bash -n "${file}" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

download_panel() {
    local tmp_file
    mkdir -p "${TARGET_BIN%/*}" || return 1
    tmp_file="$(mktemp "${TARGET_BIN}.tmp.XXXXXX")" || return 1

    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 2 --connect-timeout 8 --max-time 60 \
            -o "${tmp_file}" "${GITHUB_RAW_URL}/hy2.sh" >/dev/null 2>&1 || true
    fi

    if [[ ! -s "${tmp_file}" ]] && command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 --tries=2 -O "${tmp_file}" \
            "${GITHUB_RAW_URL}/hy2.sh" >/dev/null 2>&1 || true
    fi

    if ! verify_downloaded_panel "${tmp_file}"; then
        rm -f "${tmp_file}"
        return 1
    fi

    chmod +x "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
    mv -f "${tmp_file}" "${TARGET_BIN}" || { rm -f "${tmp_file}"; return 1; }
    return 0
}

if [[ "${BASH_SOURCE[0]:-$0}" != "$0" ]]; then
    return 0
fi

echo -e "${_green}=====================================================${_plain}"
echo -e "              欢迎使用 hy2ctl 一键部署脚本"
echo -e "${_green}=====================================================${_plain}"

# 1. 检查 root 权限
require_root
preflight_check

# 2. 安装基础依赖
PKG_MANAGER="$(detect_pkg_manager || true)"
if [[ -z "${PKG_MANAGER}" ]]; then
    err "未检测到受支持的包管理器 (apt-get/dnf/yum)。"
    exit 1
fi
if ! install_dependencies "${PKG_MANAGER}"; then
    err "基础依赖准备失败，请根据上方包管理器错误处理后重试。"
    exit 1
fi

# 3. 下载并覆盖核心面板脚本
msg "正在拉取最新的 hy2ctl 管理面板..."
if download_panel; then
    ok "面板安装完成！"
    msg "正在自动安装/更新 Hysteria2 内核..."
    if ! "${TARGET_BIN}" --install-core; then
        err "Hysteria2 内核安装/更新失败，已停止进入面板。"
        exit 1
    fi
    echo -e "-----------------------------------------------------"
    echo -e "👉 以后只需在终端输入 ${_green}hy2${_plain} 即可唤出管理面板！"
    echo -e "-----------------------------------------------------"
    sleep 2
    # 首次自动运行面板
    "${TARGET_BIN}"
else
    err "下载面板失败，请检查网络或 GitHub Raw 链接是否正确。"
    exit 1
fi
