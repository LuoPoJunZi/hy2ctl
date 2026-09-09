#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if ! grep -Fq -- "${pattern}" "${file}"; then
        fail "${label} (missing: ${pattern})"
    fi
}

assert_contains "src/panel/menu.sh" "=> 请选择操作 [0-11]:" "menu source range mismatch"
assert_contains "src/panel/menu.sh" "render_main_menu()" "menu render boundary missing"
assert_contains "src/panel/menu.sh" "dispatch_main_menu()" "menu dispatch boundary missing"
assert_contains "src/panel/menu.sh" "快捷启动: hy2" "menu source quick launch label mismatch"
assert_contains "src/panel/menu.sh" "内核版本:" "menu source status label mismatch"
assert_contains "src/panel/menu.sh" "print_sub_line" "menu source status separator mismatch"
assert_contains "src/panel/menu.sh" "节点核心管理" "menu source node section label mismatch"
assert_contains "src/panel/menu.sh" "服务运行控制" "menu source service section label mismatch"
assert_contains "src/panel/menu.sh" "(1)  节点配置（CA / 自签）" "menu source item 1 mismatch"
assert_contains "src/panel/menu.sh" "(2)  客户端配置与分享" "menu source item 2 mismatch"
assert_contains "src/panel/menu.sh" "(3)  服务启动与控制" "menu source item 3 mismatch"
assert_contains "src/panel/menu.sh" "(4)  实时运行日志" "menu source item 4 mismatch"
assert_contains "src/panel/menu.sh" "(5)  完全卸载清理" "menu source item 5 mismatch"
assert_contains "src/panel/menu.sh" "(6)  常用指令速查" "menu source item 6 mismatch"
assert_contains "src/panel/menu.sh" "(7)  Sing-box 完整模板" "menu source item 7 mismatch"
assert_contains "src/panel/menu.sh" "(8)  一键环境诊断" "menu source item 8 mismatch"
assert_contains "src/panel/menu.sh" "(9)  最近诊断报告" "menu source item 9 mismatch"
assert_contains "src/panel/menu.sh" "(10) 配置备份与恢复" "menu source item 10 mismatch"
assert_contains "src/panel/menu.sh" "(11) 面板与内核更新" "menu source item 11 mismatch"
assert_contains "src/panel/menu.sh" "(0)  退出面板" "menu source item 0 spacing mismatch"

assert_contains "README.md" "➡️ 请选择操作 [0-11]:" "README menu range mismatch"
assert_contains "README.md" "快捷启动: hy2" "README quick launch label mismatch"
assert_contains "README.md" "内核版本: v2.12.2    服务状态: 运行中" "README status label mismatch"
assert_contains "README.md" "-----------------------------------------------------" "README status separator mismatch"
assert_contains "README.md" "节点核心管理" "README node section label mismatch"
assert_contains "README.md" "服务运行控制" "README service section label mismatch"
assert_contains "README.md" "(1)  节点配置（CA / 自签）" "README menu item 1 mismatch"
assert_contains "README.md" "(2)  客户端配置与分享" "README menu item 2 mismatch"
assert_contains "README.md" "(3)  服务启动与控制" "README menu item 3 mismatch"
assert_contains "README.md" "(4)  实时运行日志" "README menu item 4 mismatch"
assert_contains "README.md" "(5)  完全卸载清理" "README menu item 5 mismatch"
assert_contains "README.md" "(6)  常用指令速查" "README menu item 6 mismatch"
assert_contains "README.md" "(7)  Sing-box 完整模板" "README menu item 7 mismatch"
assert_contains "README.md" "(8)  一键环境诊断" "README menu item 8 mismatch"
assert_contains "README.md" "(9)  最近诊断报告" "README menu item 9 mismatch"
assert_contains "README.md" "(10) 配置备份与恢复" "README menu item 10 mismatch"
assert_contains "README.md" "(11) 面板与内核更新" "README menu item 11 mismatch"
assert_contains "README.md" "(0)  退出面板" "README menu item 0 spacing mismatch"

assert_contains "install.sh" '"${TARGET_BIN}" --install-core' "installer automatic core setup missing"
assert_contains "src/main.sh" "--install-core) install_hy2_core" "panel internal core setup entry missing"
assert_contains "src/panel/menu.sh" "11) show_update_menu" "menu update submenu dispatch missing"
assert_contains "src/panel/update.sh" "(1) 安装/更新 Hysteria2 内核" "update submenu core item missing"
assert_contains "src/panel/update.sh" "(2) 更新 hy2ctl 管理面板" "update submenu panel item missing"

echo "[OK] Menu and README preview are in sync."
