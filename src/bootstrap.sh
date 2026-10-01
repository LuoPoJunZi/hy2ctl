#!/bin/bash
# 此文件同时作为生成版 hy2.sh 的开头；业务代码请修改 src/ 下对应模块。
# ==========================================
# 项目: hy2ctl 核心管理面板
# 描述: 专为恶劣网络环境打造的极简 Hysteria2 运维脚本
# ==========================================

# 交互式主面板不启用全局 errexit，各外部命令在对应流程中显式处理失败与回滚。

# --- 1. 全局变量与颜色输出 ---
sh_ver="v26.10.1"

_red="\033[0;31m"
_green="\033[0;32m"
_yellow="\033[0;33m"
_blue="\033[0;36m"
_plain="\033[0m"

HY2_CONF_DIR="/etc/hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_SERVICE="hysteria-server.service"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
HY2_DIAG_DIR="/tmp"
HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
PANEL_UPDATE_URL="https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/hy2.sh"
PANEL_TARGET_BIN="/usr/local/bin/hy2"
PANEL_BACKUP_PREFIX="/usr/local/bin/hy2.bak"
HY2_INSTALL_URL="https://get.hy2.sh/"
HY2_SECURITY_BASELINE_VERSION="2.9.2"
RECOMMENDED_HY2_VERSION="2.12.3"
DEFAULT_PORT=8443
DEFAULT_MASQUERADE_URL="https://bing.com"
DEFAULT_SELF_SNI="bing.com"
DEFAULT_UP_MBPS=50
DEFAULT_DOWN_MBPS=200
DEFAULT_CERT_TYPE=2
SELF_SNI_PRESETS=("bing.com" "www.cloudflare.com" "www.apple.com" "www.microsoft.com" "www.amazon.com")
RUNTIME_FILE_NAMES=("config.yaml" "meta.info" "server.crt" "server.key")
