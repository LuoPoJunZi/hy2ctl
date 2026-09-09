# shellcheck shell=bash
# 职责: Hysteria2 内核、服务、配置与网络诊断检查

diagnostic_check_core() {
    local core_version

    if ensure_hy2_core_installed; then
        core_version="$(get_hy2_core_version 2>/dev/null || true)"
        if [[ -z "${core_version}" ]]; then
            diagnostic_print_result "WARN" "已检测到 Hysteria2 内核，但无法读取版本。"
        elif version_at_least "${core_version}" "${RECOMMENDED_HY2_VERSION}"; then
            diagnostic_print_result "OK" "Hysteria2 内核版本: ${core_version}。"
        else
            diagnostic_print_result "WARN" "Hysteria2 内核版本 ${core_version} 低于建议版本 v${RECOMMENDED_HY2_VERSION}。"
            diagnostic_add_item \
                "Hysteria2 内核版本较旧。" \
                "建议更新，以获得移动端快速重连、IPv6 mimic 与小 MTU 稳定性修复。" \
                "菜单 (11) -> 安装/更新 Hysteria2 内核"
        fi
    else
        diagnostic_print_result "FAIL" "未检测到 Hysteria2 内核，请通过菜单 (11) 安装。"
        diagnostic_add_item \
            "未安装 Hysteria2 内核。" \
            "先安装内核，再进行节点配置与启动服务。" \
            "菜单 (11) -> 安装/更新 Hysteria2 内核"
    fi
}

diagnostic_check_service() {
    if systemctl is-enabled "${HY2_SERVICE}" >/dev/null 2>&1; then
        diagnostic_print_result "OK" "服务已设置开机自启。"
    else
        diagnostic_print_result "WARN" "服务未设置开机自启，可执行: systemctl enable ${HY2_SERVICE}"
        diagnostic_add_item \
            "服务未开启开机自启。" \
            "建议开启自启，避免重启后节点离线。" \
            "systemctl enable ${HY2_SERVICE}"
    fi

    if systemctl is-active --quiet "${HY2_SERVICE}"; then
        diagnostic_print_result "OK" "服务当前状态: 运行中。"
    else
        diagnostic_print_result "WARN" "服务当前未运行，可执行菜单 (3) 启动/重启。"
        diagnostic_add_item \
            "服务当前未运行。" \
            "先尝试启动服务，若失败再看实时日志定位原因。" \
            "systemctl restart ${HY2_SERVICE} && journalctl -u ${HY2_SERVICE} --no-pager -n 60"
    fi
}

diagnostic_check_runtime_files() {
    if [[ -f "${HY2_CONF_FILE}" ]]; then
        diagnostic_print_result "OK" "配置文件存在: ${HY2_CONF_FILE}"
    else
        diagnostic_print_result "FAIL" "配置文件不存在: ${HY2_CONF_FILE}"
        diagnostic_add_item \
            "服务配置文件缺失。" \
            "重新执行节点配置生成 config.yaml。" \
            "菜单 (1) 配置 Hysteria2 节点 (CA / 自签)"
    fi

    if read_meta_info; then
        diagnostic_print_result "OK" "节点元数据存在且可解析。"
    else
        diagnostic_print_result "WARN" "节点元数据缺失或损坏，建议重新执行菜单 (1)。"
        diagnostic_add_item \
            "节点元数据缺失或损坏。" \
            "重新生成节点配置，确保分享链接参数准确。" \
            "菜单 (1) 配置 Hysteria2 节点 (CA / 自签)"
    fi
}

diagnostic_check_server_config() {
    local listen_port cert_path key_path

    [[ -f "${HY2_CONF_FILE}" ]] || return 0

    listen_port="$(sed -n 's/^listen:[[:space:]]*:\([0-9]\+\).*/\1/p' "${HY2_CONF_FILE}" | head -n 1)"
    if [[ -n "${listen_port}" ]]; then
        diagnostic_print_result "OK" "监听端口配置为: ${listen_port}"
        if command -v ss >/dev/null 2>&1; then
            if ss -lun 2>/dev/null | grep -qE "[\:\.]${listen_port}[[:space:]]"; then
                diagnostic_print_result "OK" "检测到 UDP 端口 ${listen_port} 正在监听。"
            else
                diagnostic_print_result "WARN" "未检测到 UDP 端口 ${listen_port} 监听，可能服务未启动。"
                diagnostic_add_item \
                    "未检测到 UDP 端口 ${listen_port} 监听。" \
                    "可能服务未运行或端口被占用，请先检查服务与端口占用。" \
                    "ss -lntup | grep -E \"[:.]${listen_port}[[:space:]]\""
            fi
        else
            diagnostic_print_result "WARN" "系统未安装 ss，跳过端口监听检查。"
        fi
    else
        diagnostic_print_result "WARN" "未能从配置中解析 listen 端口。"
        diagnostic_add_item \
            "无法从配置解析 listen 端口。" \
            "请检查 config.yaml 语法与 listen 字段格式。" \
            "hysteria server -c ${HY2_CONF_FILE}"
    fi

    if grep -q '^tls:' "${HY2_CONF_FILE}"; then
        cert_path="$(sed -n 's/^[[:space:]]*cert:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
        key_path="$(sed -n 's/^[[:space:]]*key:[[:space:]]*//p' "${HY2_CONF_FILE}" | head -n 1)"
        if [[ -n "${cert_path}" && -f "${cert_path}" ]]; then
            diagnostic_print_result "OK" "自签证书文件存在: ${cert_path}"
        else
            diagnostic_print_result "FAIL" "自签证书文件缺失。"
            diagnostic_add_item \
                "自签证书文件缺失。" \
                "重新执行自签配置生成证书，或检查证书路径。" \
                "菜单 (1) -> 自签模式重新生成"
        fi
        if [[ -n "${key_path}" && -f "${key_path}" ]]; then
            diagnostic_print_result "OK" "自签私钥文件存在: ${key_path}"
        else
            diagnostic_print_result "FAIL" "自签私钥文件缺失。"
            diagnostic_add_item \
                "自签私钥文件缺失。" \
                "重新执行自签配置生成私钥，确认文件权限可读。" \
                "菜单 (1) -> 自签模式重新生成"
        fi
    elif grep -q '^acme:' "${HY2_CONF_FILE}"; then
        diagnostic_print_result "OK" "当前为 CA 证书模式。"
    else
        diagnostic_print_result "WARN" "未检测到 tls/acme 配置块，请确认配置正确。"
        diagnostic_add_item \
            "配置未识别到 tls/acme 证书块。" \
            "配置内容可能异常，建议重新生成节点配置。" \
            "菜单 (1) 重新配置节点"
    fi
}

diagnostic_check_public_ip() {
    local probe_ip

    probe_ip="$(fetch_server_ip)"
    if [[ -n "${probe_ip}" ]]; then
        diagnostic_print_result "OK" "公网 IP 探测成功: ${probe_ip}"
        if [[ -n "${ip:-}" && "${ip}" != "${probe_ip}" ]]; then
            diagnostic_print_result "WARN" "元数据 IP(${ip}) 与当前探测 IP(${probe_ip}) 不一致。"
            diagnostic_add_item \
                "元数据 IP 与当前公网 IP 不一致。" \
                "客户端可能连向旧 IP，建议更新客户端配置。" \
                "菜单 (2) 重新获取分享链接并覆盖客户端配置"
        fi
    else
        diagnostic_print_result "WARN" "公网 IP 探测失败，请检查网络连接。"
        diagnostic_add_item \
            "公网 IP 探测失败。" \
            "可能是本机网络受限或 DNS 问题，先验证基础网络连通。" \
            "curl -4 https://api.ipify.org && curl -6 https://api64.ipify.org"
    fi
}
