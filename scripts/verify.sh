#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

check_cmd() {
    local name="$1"
    if ! command -v "${name}" >/dev/null 2>&1; then
        echo "[ERROR] Missing command: ${name}"
        return 1
    fi
}

require_cmds() {
    local name
    for name in "$@"; do
        check_cmd "${name}"
    done
}

run_syntax_checks() {
    require_cmds bash
    echo "[INFO] Running bash syntax checks..."
    local file
    for file in hy2.sh install.sh src/*.sh src/*/*.sh scripts/*.sh tests/e2e/*.sh; do
        bash -n "${file}"
    done
}

run_generated_panel_check() {
    require_cmds bash cmp
    echo "[INFO] Checking generated panel consistency..."
    bash scripts/build-panel.sh --check
}

run_style_checks() {
    require_cmds bash git grep tail wc tr
    echo "[INFO] Running repository style checks..."
    bash scripts/check-style.sh
}

run_shellcheck() {
    require_cmds shellcheck
    echo "[INFO] Running shellcheck..."
    shellcheck -S error -x hy2.sh install.sh src/*.sh src/*/*.sh scripts/*.sh tests/e2e/*.sh
}

run_menu_sync_check() {
    require_cmds bash
    echo "[INFO] Checking menu/README consistency..."
    bash scripts/check-menu-sync.sh
}

run_brand_sync_check() {
    require_cmds bash git grep
    echo "[INFO] Checking project brand/repository URL consistency..."
    bash scripts/check-brand-sync.sh
}

run_version_sync_check() {
    require_cmds bash
    echo "[INFO] Checking version marker consistency..."
    bash scripts/check-version-sync.sh
}

run_release_package_check() {
    require_cmds bash
    echo "[INFO] Checking release package guardrails..."
    bash scripts/check-release-package.sh
}

run_smoke_e2e_checks() {
    require_cmds bash
    echo "[INFO] Running smoke E2E checks..."
    bash scripts/smoke-e2e.sh
}

run_bats_tests() {
    require_cmds bats
    echo "[INFO] Running bats tests..."
    bats tests/unit
}

run_config_flow_replay() {
    require_cmds bash
    echo "[INFO] Running config flow replay tests..."
    bash tests/e2e/config-flow.sh
}

run_client_render_replay() {
    require_cmds bash "${PYTHON_BIN:-python3}"
    echo "[INFO] Running client render flow tests..."
    bash tests/e2e/client-render.sh
}

run_runtime_contracts() {
    require_cmds bash
    echo "[INFO] Running runtime boundary and failure propagation checks..."
    bash tests/e2e/runtime-contracts.sh
}

run_all() {
    run_syntax_checks
    run_generated_panel_check
    run_style_checks
    run_shellcheck
    run_menu_sync_check
    run_brand_sync_check
    run_version_sync_check
    run_release_package_check
    run_smoke_e2e_checks
    run_bats_tests
    run_config_flow_replay
    run_client_render_replay
    run_runtime_contracts
}

case "${1:-all}" in
    syntax) run_syntax_checks ;;
    generated-panel) run_generated_panel_check ;;
    style) run_style_checks ;;
    shellcheck) run_shellcheck ;;
    menu-sync) run_menu_sync_check ;;
    brand-sync) run_brand_sync_check ;;
    version-sync) run_version_sync_check ;;
    release-package) run_release_package_check ;;
    smoke-e2e) run_smoke_e2e_checks ;;
    bats) run_bats_tests ;;
    config-flow) run_config_flow_replay ;;
    client-render) run_client_render_replay ;;
    runtime-contracts) run_runtime_contracts ;;
    all) run_all ;;
    *)
        echo "[ERROR] Unknown verify target: $1"
        echo "Usage: $0 [syntax|generated-panel|style|shellcheck|menu-sync|brand-sync|version-sync|release-package|smoke-e2e|bats|config-flow|client-render|runtime-contracts|all]"
        exit 1
        ;;
esac

echo "[OK] All checks passed."
