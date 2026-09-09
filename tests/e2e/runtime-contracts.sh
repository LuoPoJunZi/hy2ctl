#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HY2_LIB_ONLY=1
# shellcheck source=../../hy2.sh
source "${ROOT_DIR}/hy2.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TMP_DIR}"' EXIT
HY2_CONF_DIR="${TMP_DIR}"
HY2_CONF_FILE="${TMP_DIR}/config.yaml"
HY2_META_FILE="${TMP_DIR}/meta.info"
HY2_DIAG_DIR="${TMP_DIR}"

fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
clear() { :; }
sleep() { :; }
wait_return() { :; }

test_metadata_transaction() (
    local_key="caller-key"
    key="${local_key}"
    value="caller-value"
    # 最后一个字段故意不加换行；值中的等号和 Shell 语法必须原样保留。
    printf '%s\n' 'ip=1.2.3.4' 'port=00443' 'password=$(not-a-command)=x' 'sni=bing.com' > "${HY2_META_FILE}"
    printf '%s' 'insecure=true' >> "${HY2_META_FILE}"
    read_meta_info
    [[ "${port}" == 443 && "${password}" == '$(not-a-command)=x' ]]
    [[ "${up_mbps}" == "${DEFAULT_UP_MBPS}" && "${down_mbps}" == "${DEFAULT_DOWN_MBPS}" ]]
    [[ "${key}" == "${local_key}" && "${value}" == caller-value ]]
    printf '\nport=70000\n' >> "${HY2_META_FILE}"
    if read_meta_info; then fail 'Invalid metadata accepted'; fi
    [[ -z "${ip}${port}${password}${sni}${insecure}${up_mbps}${down_mbps}" ]]
    ip="old-node"
    HY2_META_FILE="${TMP_DIR}/missing-meta"
    if read_meta_info; then fail 'Missing metadata accepted'; fi
    [[ -z "${ip}" ]]
    echo '[OK] Metadata publication is all-or-nothing, including legacy files.'
)

test_input_contract() (
    local_answer="unchanged"
    read_input '' local_answer <<< ''
    [[ -z "${local_answer}" ]]
    if read_input '' local_answer < /dev/null; then fail 'EOF accepted'; fi
    if collect_hy2_connection_settings < /dev/null; then fail 'Connection EOF accepted'; fi
    if collect_hy2_certificate_settings <<< '2'; then fail 'SNI EOF accepted'; fi
    if collect_hy2_certificate_settings <<< $'1\nexample.com'; then fail 'Email EOF accepted'; fi
    # 检查每个连接输入边界；未完成输入不能触发部署。
    ensure_hy2_core_installed() { return 0; }
    prepare_hy2_config_change() { fail 'Interrupted input reached deployment'; }
    local lines input=''
    for ((lines = 0; lines < 7; lines++)); do
        if config_hy2 < <(printf '%s' "${input}"); then fail 'Incomplete configuration accepted'; fi
        input+=$'\n'
    done
    echo '[OK] Empty lines use defaults; incomplete input never reaches deployment.'
)

test_menu_contract() (
    hysteria() { printf 'Version: v2.12.2\n'; }
    systemctl() { return 0; }
    # 有界地检测 EOF 忙循环，防止回归测试自身无限运行。
    draws=0
    render_main_menu() { draws=$((draws + 1)); ((draws < 3)) || fail 'Menu spins on EOF'; }
    main_menu < /dev/null
    [[ "${draws}" == 1 ]]
    # 子菜单复用 clear，每个测试至多允许重绘两次。
    clear() { draws=$((draws + 1)); ((draws < 3)) || fail 'Submenu spins on EOF'; }
    local menu
    for menu in service_control_menu show_backup_restore_menu show_update_menu; do
        draws=0
        "${menu}" < /dev/null
        [[ "${draws}" == 1 ]]
    done
    # 导航参数局部化，不污染调用者状态；业务失败后仍可退出面板。
    menu_num='outer-menu'
    action='outer-action'
    draws=0
    dispatch_main_menu() { return 1; }
    main_menu <<< $'1\n0' || fail 'Menu did not recover from action failure'
    [[ "${menu_num}" == outer-menu && "${action}" == outer-action ]]
    echo '[OK] Menu loops terminate on EOF and isolate navigation state.'
)

test_live_menu_status() (
    version=v2.12.2
    active=1
    hysteria() { printf 'Version: %s\n' "${version}"; }
    systemctl() { [[ "${active}" == 1 ]]; }
    output="$(render_main_menu)"
    [[ "${output}" == *v2.12.2* && "${output}" == *运行中* ]]
    version=v2.13.0
    active=0
    output="$(render_main_menu)"
    [[ "${output}" == *v2.13.0* && "${output}" == *未运行* ]]
    echo '[OK] Menu version and service status refresh without stale caches.'
)

test_version_probe() (
    hysteria() { printf 'Version: v2.12.2\nBuild: v1.0.0\n'; }
    # 不允许退回 grep/head 管道，兼顾结果与进程开销回归。
    grep() { fail 'Unexpected grep process'; }
    head() { fail 'Unexpected head process'; }
    [[ "$(get_hy2_core_version)" == v2.12.2 ]]
    hysteria() { printf 'Version: v9.9.9\n'; return 1; }
    if output="$(get_hy2_core_version)"; then fail 'Failed version probe accepted'; fi
    [[ -z "${output}" ]]
    hysteria() { printf 'unknown\n'; }
    if get_hy2_core_version; then fail 'Unparseable version accepted'; fi
    echo '[OK] Version probe propagates failures without grep/head.'
)

test_writer_contract() (
    write_file_atomic() { printf '%s\n' "$1"; return 1; }
    if write_ca_config 443 example.com a@example.com secret https://bing.com; then fail 'CA write failure swallowed'; fi
    if write_self_signed_config 443 secret https://bing.com; then fail 'TLS write failure swallowed'; fi
    if write_meta_info 1.2.3.4 443 secret bing.com true 50 200; then fail 'Metadata write failure swallowed'; fi
    echo '[OK] All config writers preserve atomic-write failures.'
)

test_template_contract() (
    local payload
    if payload="$(render_singbox_full_template 1.2.3.4 443 50 200 secret bing.com true invalid)"; then
        fail 'Invalid pin accepted'
    fi
    [[ -z "${payload}" ]]
    render_singbox_dns_section() { return 1; }
    render_singbox_route_section() { fail 'Render continued after failed section'; }
    if render_singbox_full_template 1.2.3.4 443 50 200 secret bing.com false > /dev/null; then
        fail 'Template section failure swallowed'
    fi
    echo '[OK] Template validates pins before output and stops on section failure.'
)

test_download_contract() (
    curl() { printf '%s\n' "$@" > "${TMP_DIR}/curl-args"; return 28; }
    if download_script https://example.com/script "${TMP_DIR}/download"; then fail 'Download failure swallowed'; fi
    local args
    args="$(< "${TMP_DIR}/curl-args")"
    [[ "${args}" == *$'--max-time\n120'* && "${args}" == *$'--connect-timeout\n8'* ]]
    [[ "${args}" == *$'--retry\n2'* && "${args}" == *"${TMP_DIR}/download"* ]]
    echo '[OK] Script downloads have bounded retries and per-attempt deadlines.'
)

test_syntax_gate() (
    # 在独立临时工程中注入末尾文件语法错误，不触碰真实源码。
    local fixture="${TMP_DIR}/syntax-fixture"
    mkdir -p "${fixture}/scripts" "${fixture}/src/core" "${fixture}/tests/e2e"
    cp "${ROOT_DIR}/scripts/verify.sh" "${fixture}/scripts/verify.sh"
    local file
    for file in hy2.sh install.sh src/bootstrap.sh src/core/output.sh tests/e2e/first.sh; do
        printf '#!/bin/bash\n' > "${fixture}/${file}"
    done
    printf 'if then\n' > "${fixture}/tests/e2e/zz-broken.sh"
    if bash "${fixture}/scripts/verify.sh" syntax > "${TMP_DIR}/syntax.log" 2>&1; then
        fail 'Syntax gate missed a later file'
    fi
    grep -Fq 'zz-broken.sh' "${TMP_DIR}/syntax.log"
    printf '#!/bin/bash\n' > "${fixture}/tests/e2e/zz-broken.sh"
    bash "${fixture}/scripts/verify.sh" syntax > /dev/null
    echo '[OK] Syntax gate checks every file, including later glob matches.'
)

test_metadata_transaction
test_input_contract
test_menu_contract
test_live_menu_status
test_version_probe
test_writer_contract
test_template_contract
test_download_contract
test_syntax_gate
echo '[OK] Runtime contract checks passed.'
