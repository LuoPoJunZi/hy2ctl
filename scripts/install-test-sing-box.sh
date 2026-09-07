#!/usr/bin/env bash
set -euo pipefail

SING_BOX_TEST_VERSION="1.14.0"
SING_BOX_TEST_SHA256="2375de6999f4f56ab46b4fc5ddf26a6aba1d3e61a0f4e7ddec2f4690457d5f63"

normalize_path() {
    local path="$1"
    if command -v cygpath >/dev/null 2>&1 && [[ "${path}" =~ ^[A-Za-z]:[\\/] ]]; then
        cygpath -u "${path}"
    else
        printf '%s\n' "${path}"
    fi
}

runner_temp="$(normalize_path "${RUNNER_TEMP:-/tmp}")"
archive="${runner_temp}/sing-box-${SING_BOX_TEST_VERSION}-linux-amd64.tar.gz"
install_dir="${runner_temp}/sing-box-${SING_BOX_TEST_VERSION}"
download_url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_TEST_VERSION}/sing-box-${SING_BOX_TEST_VERSION}-linux-amd64.tar.gz"

for dependency in curl sha256sum tar; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
        echo "[ERROR] Missing command: ${dependency}"
        exit 1
    fi
done

curl --fail --location --retry 3 "${download_url}" --output "${archive}"
echo "${SING_BOX_TEST_SHA256}  ${archive}" | sha256sum --check --strict
mkdir -p "${install_dir}"
tar -xzf "${archive}" -C "${install_dir}" --strip-components=1

if [[ -n "${GITHUB_PATH:-}" ]]; then
    github_path_file="$(normalize_path "${GITHUB_PATH}")"
    echo "${install_dir}" >> "${github_path_file}"
else
    echo "[INFO] Add ${install_dir} to PATH to use the pinned sing-box test binary."
fi
