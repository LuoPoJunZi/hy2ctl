# shellcheck shell=bash
# 职责: Hysteria2 配置变更的准备、证书应用与启用

prepare_hy2_config_change() {
    if ! mkdir -p "${HY2_CONF_DIR}"; then
        err "创建配置目录失败: ${HY2_CONF_DIR}"
        sleep 2
        return 1
    fi
    set_config_dir_permissions
    if ! backup_runtime_files; then
        err "备份当前配置失败，已中止以避免覆盖现有配置。"
        sleep 2
        return 1
    fi
}

apply_hy2_ca_config() {
    local port="$1"
    local domain="$2"
    local email="$3"
    local password="$4"
    local masquerade_url="$5"

    if ! rm -f -- "${HY2_CONF_DIR}/server.crt" "${HY2_CONF_DIR}/server.key"; then
        abort_pending_config_change "清理旧自签证书失败"
        sleep 2
        return 1
    fi
    if ! write_ca_config "${port}" "${domain}" "${email}" "${password}" "${masquerade_url}"; then
        abort_pending_config_change "写入 CA 配置失败"
        sleep 2
        return 1
    fi
    set_server_config_permissions
}

apply_hy2_self_signed_config() {
    local port="$1"
    local password="$2"
    local masquerade_url="$3"
    local sni="$4"

    msg "正在生成高强度自签名证书..."
    if ! generate_self_signed_certificate "${sni}"; then
        abort_pending_config_change "自签证书生成失败"
        sleep 2
        return 1
    fi

    if ! get_certificate_sha256 "${HY2_CONF_DIR}/server.crt" >/dev/null; then
        abort_pending_config_change "无法计算自签证书 SHA-256 指纹"
        sleep 2
        return 1
    fi

    set_tls_file_permissions

    if ! write_self_signed_config "${port}" "${password}" "${masquerade_url}"; then
        abort_pending_config_change "写入自签配置失败"
        sleep 2
        return 1
    fi
    set_server_config_permissions
}

activate_hy2_config() {
    local port="$1"
    local password="$2"
    local sni="$3"
    local insecure="$4"
    local up_mbps="$5"
    local down_mbps="$6"
    local server_ip

    if ! server_ip="$(fetch_server_ip)" || ! is_valid_ip "${server_ip}"; then
        abort_pending_config_change "无法获取服务器 IP"
        sleep 2
        return 1
    fi
    if ! is_public_ip "${server_ip}"; then
        msg "公网 IP 探测失败，当前使用本机非公网地址 ${server_ip}；NAT/内网部署请确认客户端应连接的地址与端口映射。"
    fi

    if ! write_meta_info "${server_ip}" "${port}" "${password}" "${sni}" "${insecure}" "${up_mbps}" "${down_mbps}"; then
        abort_pending_config_change "写入节点元数据失败"
        sleep 2
        return 1
    fi
    chmod 600 "${HY2_META_FILE}" >/dev/null 2>&1 || true

    msg "检测到服务运行用户: $(get_service_run_user)"
    msg "正在重启 Hysteria2 服务以应用新配置..."
    if ! restart_service_with_rollback; then
        sleep 2
        return 1
    fi
    ok "Hysteria2 节点配置并启动成功！"
    sleep 2
}
