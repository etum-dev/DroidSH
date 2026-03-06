#!/usr/bin/env bash
echo "[^owo^] iOS Frida version switcher"
echo "Usage: ./ios-frida.sh <version> [arch]"
# Default ios-arm64 (modern)

set -euo pipefail

FRIDA_DIR="frida_versions"
IPROXY_PORT=2222
DEVICE_SSH_PORT=22
DEVICE_USER="mobile"
FRIDA_REMOTE_PATH="/private/var/mobile"

arch="${2:-ios-arm64}"

ensure_iproxy() {
    if pgrep -x iproxy >/dev/null 2>&1; then
        echo "iproxy already running"
    else
        echo "Starting iproxy on localhost:${IPROXY_PORT} -> device:${DEVICE_SSH_PORT}"
        iproxy "${IPROXY_PORT}" "${DEVICE_SSH_PORT}" &
        IPROXY_PID=$!
        sleep 1
        pgrep -x iproxy >/dev/null 2>&1 || die "iproxy failed to start. Is a device connected?"
        echo "[*] iproxy started (pid ${IPROXY_PID})"
    fi
}

ssh_device() {
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        -p "${IPROXY_PORT}" \
        "${DEVICE_USER}@localhost" "$@"
}

scp_to_device() {
    scp -o StrictHostKeyChecking=no \
        -P "${IPROXY_PORT}" \
        "$1" "${DEVICE_USER}@localhost:$2"
}

setup_dirs() {
    local version="$1"
    mkdir -p "${FRIDA_DIR}/${version}"
    echo "[*] Version directory: ${FRIDA_DIR}/${version}"
}

setup_venv() {
    local version="$1"
    local venv_dir="${FRIDA_DIR}/${version}/venv"

    if [[ -d "${venv_dir}" ]]; then
        echo "Venv already exists: ${venv_dir}"
    else
        echo "Creating venv: ${venv_dir}"
        python3 -m venv "${venv_dir}"

        "${venv_dir}/bin/pip" install --upgrade pip
        echo "[*] Installing frida==${version} and frida-tools into venv"
        "${venv_dir}/bin/pip" install "frida==${version}" frida-tools
    fi


}

download_server() {
    local filename="frida_${version}_iphoneos-${arch#ios-}.deb"
    local dest="${FRIDA_DIR}/${version}/${filename}"

    echo " ${version}"
    download_url=$(curl -sf "https://api.github.com/repos/frida/frida/releases/tags/${version}" \
        | jq -r --arg name "${filename}" '.assets[] | select(.name == $name) | .browser_download_url')


    echo "Downloading: ${download_url}"
    curl -L --progress-bar -o "${dest}" "${download_url}"

    echo "${FRIDA_DIR}/${version}/${filename}" 
}

install_on_device() {
    local version="$1"
    local binary="${FRIDA_DIR}/${version}/frida_${version}_iphoneos-arm64.deb"

    [[ -f "${binary}" ]] || echo "Binary not found at ${binary}"

    ensure_iproxy
    # TODO - fix so it doesnt prompt every step. Could automate a keygen?
    echo "checking SSH connectivity..."
    ssh_device "echo connected" || echo "SSH to device failed :("

    echo "Stopping any running frida-server on device..."
    ssh_device "killall frida-server 2>/dev/null || true"

    echo "ヾ(^w^*) Uploading frida-server ${version} to device..."
    scp_to_device "${binary}" "${FRIDA_REMOTE_PATH}"

    echo "Setting permissions on device..."
    ssh_device "chmod +x ${FRIDA_REMOTE_PATH}"

    echo "[*] Starting frida-server in background..."
    ssh_device "nohup ${FRIDA_REMOTE_PATH} &>/tmp/frida-server.log &"

}

usage() {
    cat <<EOF
Usage: $0 <version> [arch] [command]

  version   Frida release tag, e.g. 13.3.7
  arch      Default: ios-arm64  (alternatives: ios-arm, ios-x86_64)
  command   download | install | setup | all (default: all)

Examples:
  $0 <version>                    # download + venv + install on device
  $0 <version> ios-arm64 download # download binary only
  $0 <version> ios-arm64 setup    # download + venv only (no device)
EOF
    exit 1
}

[[ -z "${1:-}" ]] && usage

version="$1"
cmd="${3:-all}"

echo "Frida version : ${version}"
echo "Arch          : ${arch}"
echo "Command       : ${cmd}"
echo "( ーoー)o━━☆[[[[Д]]]]ゴーーーン！！"

setup_dirs "${version}"

case "${cmd}" in
    download)
        download_server "${version}"
        ;;
    setup)
        download_server "${version}"
        setup_venv "${version}"
        ;;
    all)
        download_server "${version}"
        setup_venv "${version}"
        install_on_device "${version}"
        ;;
    *)
        echo "Unknown command '${cmd}'. Expected: download | setup | all"
        ;;
esac

echo ""
echo ":D !!! Done!"
