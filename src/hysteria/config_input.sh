# shellcheck shell=bash
# 职责: Hysteria2 节点配置输入收集与校验

reset_hy2_config_draft() {
    HY2_DRAFT_PORT=""
    HY2_DRAFT_PASSWORD=""
    HY2_DRAFT_MASQUERADE_URL=""
    HY2_DRAFT_UP_MBPS=""
    HY2_DRAFT_DOWN_MBPS=""
    HY2_DRAFT_CERT_TYPE=""
    HY2_DRAFT_DOMAIN=""
    HY2_DRAFT_EMAIL=""
    HY2_DRAFT_SNI=""
    HY2_DRAFT_INSECURE=""
}

collect_hy2_connection_settings() {
    local default_pwd

    read_input " => 请设置监听端口 (默认 ${DEFAULT_PORT}): " HY2_DRAFT_PORT || return 1
    [[ -z "${HY2_DRAFT_PORT}" ]] && HY2_DRAFT_PORT="${DEFAULT_PORT}"
    if ! is_valid_port "${HY2_DRAFT_PORT}"; then
        err "端口无效，请输入 1-65535 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_PORT="$((10#${HY2_DRAFT_PORT}))"

    if ! default_pwd="$(openssl rand -hex 16)" || [[ -z "${default_pwd}" ]]; then
        err "生成随机认证密码失败，请检查 openssl。"
        sleep 2
        return 1
    fi
    read_input " => 请设置认证密码 (默认随机: ${default_pwd}): " HY2_DRAFT_PASSWORD || return 1
    [[ -z "${HY2_DRAFT_PASSWORD}" ]] && HY2_DRAFT_PASSWORD="${default_pwd}"

    read_input " => 请设置伪装网址 (默认 ${DEFAULT_MASQUERADE_URL}): " HY2_DRAFT_MASQUERADE_URL || return 1
    [[ -z "${HY2_DRAFT_MASQUERADE_URL}" ]] && HY2_DRAFT_MASQUERADE_URL="${DEFAULT_MASQUERADE_URL}"
    if ! is_valid_url "${HY2_DRAFT_MASQUERADE_URL}"; then
        err "伪装网址格式无效，必须以 http:// 或 https:// 开头。"
        sleep 2
        return 1
    fi

    read_input " => 请设置上行带宽 Mbps (默认 ${DEFAULT_UP_MBPS}): " HY2_DRAFT_UP_MBPS || return 1
    [[ -z "${HY2_DRAFT_UP_MBPS}" ]] && HY2_DRAFT_UP_MBPS="${DEFAULT_UP_MBPS}"
    if ! is_positive_integer "${HY2_DRAFT_UP_MBPS}"; then
        err "上行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_UP_MBPS="$((10#${HY2_DRAFT_UP_MBPS}))"

    read_input " => 请设置下行带宽 Mbps (默认 ${DEFAULT_DOWN_MBPS}): " HY2_DRAFT_DOWN_MBPS || return 1
    [[ -z "${HY2_DRAFT_DOWN_MBPS}" ]] && HY2_DRAFT_DOWN_MBPS="${DEFAULT_DOWN_MBPS}"
    if ! is_positive_integer "${HY2_DRAFT_DOWN_MBPS}"; then
        err "下行带宽无效，请输入大于 0 的整数。"
        sleep 2
        return 1
    fi
    HY2_DRAFT_DOWN_MBPS="$((10#${HY2_DRAFT_DOWN_MBPS}))"
}

pick_self_signed_sni() {
    local pick custom_sni
    PICKED_SNI=""
    echo -e " [*] 请选择自签 SNI 预设域名："
    echo -e "     (1) ${SELF_SNI_PRESETS[0]} (默认)"
    echo -e "     (2) ${SELF_SNI_PRESETS[1]}"
    echo -e "     (3) ${SELF_SNI_PRESETS[2]}"
    echo -e "     (4) ${SELF_SNI_PRESETS[3]}"
    echo -e "     (5) ${SELF_SNI_PRESETS[4]}"
    echo -e "     (0) 手动输入域名"
    read_input " [*] 请选择 [0-5] (默认 1): " pick || return 1
    [[ -z "${pick}" ]] && pick=1

    case "${pick}" in
        1) PICKED_SNI="${SELF_SNI_PRESETS[0]}" ;;
        2) PICKED_SNI="${SELF_SNI_PRESETS[1]}" ;;
        3) PICKED_SNI="${SELF_SNI_PRESETS[2]}" ;;
        4) PICKED_SNI="${SELF_SNI_PRESETS[3]}" ;;
        5) PICKED_SNI="${SELF_SNI_PRESETS[4]}" ;;
        0)
            read_input " [*] 请输入用于伪装的 SNI 域名 (默认 ${DEFAULT_SELF_SNI}): " custom_sni || return 1
            [[ -z "${custom_sni}" ]] && custom_sni="${DEFAULT_SELF_SNI}"
            PICKED_SNI="${custom_sni}"
            ;;
        *)
            err "输入无效，已使用默认 SNI: ${DEFAULT_SELF_SNI}"
            PICKED_SNI="${DEFAULT_SELF_SNI}"
            ;;
    esac
}

collect_hy2_certificate_settings() {
    echo -e "\n[*] 请选择证书模式："
    echo -e "  (1) CA 域名证书 (推荐，需要提前将域名解析到本 VPS)"
    echo -e "  (2) 自签证书 (默认，无需域名，直接使用 IP 连通)"
    read_input " => 请选择 [1-2] (默认 ${DEFAULT_CERT_TYPE}): " HY2_DRAFT_CERT_TYPE || return 1
    [[ -z "${HY2_DRAFT_CERT_TYPE}" ]] && HY2_DRAFT_CERT_TYPE="${DEFAULT_CERT_TYPE}"
    if [[ "${HY2_DRAFT_CERT_TYPE}" != "1" && "${HY2_DRAFT_CERT_TYPE}" != "2" ]]; then
        err "证书模式输入无效，请输入 1 或 2。"
        sleep 2
        return 1
    fi

    if [[ "${HY2_DRAFT_CERT_TYPE}" == "1" ]]; then
        read_input " [*] 请输入已解析到本机的域名: " HY2_DRAFT_DOMAIN || return 1
        if ! is_valid_domain "${HY2_DRAFT_DOMAIN}"; then
            err "域名格式无效，请输入有效域名（例如 example.com）。"
            sleep 2
            return 1
        fi
        read_input " [*] 请输入邮箱 (用于自动申请证书，随意填): " HY2_DRAFT_EMAIL || return 1
        [[ -z "${HY2_DRAFT_EMAIL}" ]] && HY2_DRAFT_EMAIL="admin@${HY2_DRAFT_DOMAIN}"
        if ! is_valid_email "${HY2_DRAFT_EMAIL}"; then
            err "邮箱格式无效，请重新输入。"
            sleep 2
            return 1
        fi

        HY2_DRAFT_SNI="${HY2_DRAFT_DOMAIN}"
        HY2_DRAFT_INSECURE="false"
    else
        pick_self_signed_sni || return 1
        HY2_DRAFT_SNI="${PICKED_SNI}"
        if ! is_valid_domain "${HY2_DRAFT_SNI}"; then
            err "SNI 域名格式无效，请输入有效域名。"
            sleep 2
            return 1
        fi
        HY2_DRAFT_INSECURE="true"
    fi
}
