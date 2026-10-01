# shellcheck shell=bash
# 职责: 纯 Bash IPv4/IPv6 格式校验与公网候选地址筛选；不证明实际连通性

is_valid_ipv4() {
    local address="$1" octet
    local -a octets=()
    [[ "${address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<< "${address}"
    for octet in "${octets[@]}"; do
        [[ "${octet}" == 0 || "${octet}" != 0* ]] || return 1
        (( 10#${octet} <= 255 )) || return 1
    done
}

expand_ipv6_address() {
    local address="${1,,}" tail left right group zeros expanded=""
    local group_pattern='[0-9a-f]{1,4}(:[0-9a-f]{1,4})*'
    local -a left_groups=() right_groups=() groups=() octets=()
    [[ ${#address} -le 45 && "${address}" == *:* && "${address}" =~ ^[0-9a-f:.]+$ ]] || return 1
    if [[ "${address}" == *.* ]]; then
        tail="${address##*:}"
        is_valid_ipv4 "${tail}" || return 1
        IFS=. read -r -a octets <<< "${tail}"
        printf -v tail '%x:%x' "$((10#${octets[0]} * 256 + 10#${octets[1]}))" "$((10#${octets[2]} * 256 + 10#${octets[3]}))"
        address="${address%:*}:${tail}"
    fi
    if [[ "${address}" == *::* ]]; then
        left="${address%%::*}"
        right="${address#*::}"
        [[ -z "${left}" || "${left}" =~ ^${group_pattern}$ ]] || return 1
        [[ -z "${right}" || "${right}" =~ ^${group_pattern}$ ]] || return 1
        IFS=: read -r -a left_groups <<< "${left}"
        IFS=: read -r -a right_groups <<< "${right}"
        zeros=$((8 - ${#left_groups[@]} - ${#right_groups[@]}))
        (( zeros > 0 )) || return 1
        groups=("${left_groups[@]}")
        while (( zeros > 0 )); do groups+=(0); zeros=$((zeros - 1)); done
        groups+=("${right_groups[@]}")
    else
        [[ "${address}" =~ ^${group_pattern}$ ]] || return 1
        IFS=: read -r -a groups <<< "${address}"
        (( ${#groups[@]} == 8 )) || return 1
    fi
    # 完成校验后才输出，避免调用方使用部分展开结果。
    for group in "${groups[@]}"; do
        printf -v group '%04x' "$((16#${group}))"
        expanded+="${expanded:+:}${group}"
    done
    printf '%s\n' "${expanded}"
}

is_valid_ip() {
    is_valid_ipv4 "$1" || expand_ipv6_address "$1" >/dev/null
}

is_public_ip() {
    local address="$1" expanded first second third index
    local -a parts=()
    if is_valid_ipv4 "${address}"; then
        IFS=. read -r -a parts <<< "${address}"
        first="${parts[0]}"; second="${parts[1]}"; third="${parts[2]}"
        # IANA 特殊用途：私网、CGNAT、回环、链路本地、文档、测试、组播及保留地址。
        (( first != 0 && first != 10 && first != 127 && first < 224 )) || return 1
        (( first != 100 || second < 64 || second > 127 )) || return 1
        (( first != 169 || second != 254 )) || return 1
        (( first != 172 || second < 16 || second > 31 )) || return 1
        (( first != 192 || second != 168 )) || return 1
        if (( first == 192 && second == 0 )); then
            (( (third != 0 && third != 2) || (third == 0 && (parts[3] == 9 || parts[3] == 10)) )) || return 1
        fi
        (( first != 192 || second != 88 || third != 99 )) || return 1
        (( first != 198 || (second != 18 && second != 19) )) || return 1
        (( first != 198 || second != 51 || third != 100 )) || return 1
        (( first != 203 || second != 0 || third != 113 )) || return 1
        return 0
    fi
    expanded="$(expand_ipv6_address "${address}")" || return 1
    IFS=: read -r -a parts <<< "${expanded}"
    for index in "${!parts[@]}"; do parts[index]="$((16#${parts[index]}))"; done
    first="${parts[0]}"; second="${parts[1]}"; third="${parts[2]}"
    # NAT64 标准前缀；嵌入的 IPv4 地址也必须是公网候选。
    if (( first == 0x64 && second == 0xff9b && (third | parts[3] | parts[4] | parts[5]) == 0 )); then
        is_public_ip "$((parts[6] >> 8)).$((parts[6] & 255)).$((parts[7] >> 8)).$((parts[7] & 255))"
        return
    fi
    (( first >= 0x2000 && first <= 0x3fff )) || return 1
    (( first != 0x2001 || second != 0xdb8 )) || return 1
    (( first != 0x3fff || second >= 0x1000 )) || return 1
    if (( first == 0x2001 && second < 0x200 )); then
        (( second == 0 || second == 3 || (second == 4 && third == 0x112) || (second >= 0x20 && second <= 0x3f) )) && return 0
        (( second == 1 && (third | parts[3] | parts[4] | parts[5] | parts[6]) == 0 && parts[7] >= 1 && parts[7] <= 3 )) || return 1
    fi
    return 0
}
