# shellcheck shell=bash
# Shell 回放测试共用断言；Bats 用例仍可使用原生断言。

fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected: $2, actual: $1)"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || fail "$3 (missing: $2)"
}

assert_contains_file() {
    grep -Fq -- "$2" "$1" || fail "$3 (missing: $2)"
}

assert_file_equals() {
    local actual
    actual="$(cat "$1")" || fail "Cannot read $1"
    assert_eq "${actual}" "$2" "$3"
}
