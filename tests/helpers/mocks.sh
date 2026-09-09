# shellcheck shell=bash
# 仅在测试中显式 source；不安装真实服务、不访问 journal。

__mock_systemctl_mode="always_success"
__mock_systemctl_calls=0
__mock_journalctl_log=""

systemctl() {
    case "${1:-}" in
        show) printf 'root\n' ;;
        restart)
            __mock_systemctl_calls=$((__mock_systemctl_calls + 1))
            case "${__mock_systemctl_mode}" in
                always_success) return 0 ;;
                fail_then_success) (( __mock_systemctl_calls > 1 )) ;;
                always_fail) return 1 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 0 ;;
    esac
}

journalctl() { printf '%s\n' "${__mock_journalctl_log}"; }
