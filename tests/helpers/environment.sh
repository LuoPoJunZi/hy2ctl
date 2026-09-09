# shellcheck shell=bash
# 加载函数不运行面板；测试文件只能写入本次创建的临时目录。

TEST_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_FIXTURE_DIR="${TEST_ROOT_DIR}/tests/fixtures"

test_load_panel() {
    export HY2_LIB_ONLY=1
    # shellcheck source=../../hy2.sh
    source "${TEST_ROOT_DIR}/hy2.sh"
}

test_create_environment() {
    TEST_TMP_DIR="$(mktemp -d -t hy2ctl-test.XXXXXX)" || return 1
    HY2_CONF_DIR="${TEST_TMP_DIR}/etc-hysteria"
    HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
    HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
    HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
    HY2_DIAG_DIR="${TEST_TMP_DIR}"
    HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
    mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"
}

test_cleanup_environment() {
    [[ -n "${TEST_TMP_DIR:-}" && "${TEST_TMP_DIR##*/}" == hy2ctl-test.* ]] || return 1
    rm -rf -- "${TEST_TMP_DIR}"
}
