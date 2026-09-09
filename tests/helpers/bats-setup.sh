# shellcheck shell=bash
# 由每个职责测试文件加载；每个用例创建独立环境。

setup() {
    # shellcheck source=environment.sh
    source "${BATS_TEST_DIRNAME}/../helpers/environment.sh"
    test_load_panel
    test_create_environment
    TMP_DIR="${TEST_TMP_DIR}"
    # shellcheck source=mocks.sh
    source "${BATS_TEST_DIRNAME}/../helpers/mocks.sh"
}

teardown() {
    test_cleanup_environment
}
