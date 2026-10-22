# shellcheck shell=bash
# 职责: 客户端配置查看流程编排

show_info() {
    if ! require_meta_info; then
        return
    fi

    local cert_sha="" cert_public_key_sha=""
    if [[ "${insecure}" == "true" ]]; then
        cert_sha="$(get_certificate_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
        cert_public_key_sha="$(get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
    fi

    print_client_summary "${cert_sha}" "${cert_public_key_sha}"

    if ! ensure_client_export_material "${cert_sha}" "${cert_public_key_sha}"; then
        return 1
    fi

    print_client_security_notice

    if [[ "${insecure}" == "true" ]]; then
        print_v2rayn_insecure_notice
    fi

    if ! print_client_exports "${cert_sha}" "${cert_public_key_sha}"; then
        return 1
    fi
    print_line
    wait_return
}
