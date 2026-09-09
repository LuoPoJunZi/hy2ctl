#!/usr/bin/env bash
# 兼容旧开发命令；实际用例统一放在 tests/e2e。
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "${ROOT_DIR}/tests/e2e/smoke.sh" "$@"
