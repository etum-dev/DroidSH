#!/usr/bin/env bash
echo "[^owo^] iOS Frida version switcher"
echo "Usage: ./ios-frida.sh <version> [arch]"

set -euo pipefail

FRIDA_DIR="frida_versions"
IPROXY_PORT=2222
DEVICE_SSH_PORT=22
DEVICE_USER="mobile"
DEVICE_TMP="/var/jb/tmp"
API="https://api.github.com/repos/frida/frida"
TMP_BODY="/tmp/droidsh"

arch="${2:-ios-arm64}"

die()  { printf '[!] %s\n' "$*" >&2; exit 1; }
warn() { printf '[~] %s\n' "$*" >&2; }

require_tools() {
    local missing=()
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

list_versions() {
    local limit="${1:-30}" status
    status="$(curl -sS -o "${TMP_BODY}" -w '%{http_code}' "${API}/releases?per_page=${limit}")"

    case "${status}" in
        200) ;;
        403) die "GitHub API rate limit hit while listing releases." ;;
        *)   die "error: GitHub API returned HTTP ${status} while listing releases." ;;
    esac

    jq -r '.[] | .tag_name' < "${TMP_BODY}"
    rm -f "${TMP_BODY}"
}

suggest_versions() {
    local wanted="$1" major all matches
    major="${wanted%%.*}"

    all="$(list_versions 100)" || return 0

    matches="$(printf '%s\n' "${all}" | grep "^${major}\." || true)"
    if [[ -n "${matches}" ]]; then
        warn "Available ${major}.x releases:"
        printf '%s\n' "${matches}" | head -n 10 | sed 's/^/      /' >&2
    else
        warn "Most recent releases:"
        printf '%s\n' "${all}" | head -n 10 | sed 's/^/      /' >&2
    fi
}

resolve_release() {
    local version="$1" status body
    status="$(curl -sS -o "${TMP_BODY}" -w '%{http_code}' "${API}/releases/tags/${version}")"
    body="$(cat "${TMP_BODY}")"
    rm -f "${TMP_BODY}"

    case "${status}" in
        200)
            printf '%s' "${body}"
            return 0
            ;;
        404)
            warn "No Frida release tagged '${version}'."
            suggest_versions "${version}"
            die "Aborting: unknown version."
            ;;
        403)
            die "GitHub API rate limit hit (not a bad version number)."
            ;;
        *)
            die "HTTP ${status} for tag '${version}'."
            ;;
    esac
}

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
    local version="$1" arch="$2"
    local filename="frida_${version}_iphoneos-${arch#ios-}.deb"
    local dest="${FRIDA_DIR}/${version}/${filename}"
    local release_json download_url

    echo "[*] Looking up release ${version}"
    release_json="$(resolve_release "${version}")"

    download_url=$(printf '%s' "${release_json}" \
        | jq -r --arg name "${filename}" '.assets[] | select(.name == $name) | .browser_download_url')

    [[ -n "${download_url}" && "${download_url}" != "null" ]] \
        || die "Release ${version} has no asset named ${filename}"

    echo "Downloading: ${download_url}"
    curl -fL --progress-bar -o "${dest}" "${download_url}" || die "Download failed"

    echo "[*] Saved to ${dest}"
}

install_on_device() {
    local version="$1" arch="$2"
    local filename="frida_${version}_iphoneos-${arch#ios-}.deb"
    local binary="${FRIDA_DIR}/${version}/${filename}"

    [[ -f "${binary}" ]] || die "Binary not found at ${binary}"

    ensure_iproxy

    echo "checking SSH connectivity..."
    ssh_device "echo connected" || die "SSH to device failed :("

    echo "Stopping any running frida-server on device..."
    ssh_device "killall frida-server 2>/dev/null || true"

    echo "ヾ(^w^*) Uploading frida-server ${version} to device..."
    ssh_device "mkdir -p ${DEVICE_TMP}"
    scp_to_device "${binary}" "${DEVICE_TMP}/${filename}" || die "Upload failed"

    echo "[*] Installing package..."
    ssh_device "dpkg -i ${DEVICE_TMP}/${filename}" || die "dpkg -i failed"
    ssh_device "rm -f ${DEVICE_TMP}/${filename}"

    echo "[*] Starting frida-server in background..."
    ssh_device "nohup /var/jb/usr/sbin/frida-server >/tmp/frida-server.log 2>&1 &"
}

usage() {
    cat <<EOF
Usage: $0 <version> [arch] [command]

  version   Frida release tag, e.g. 17.18.0
  arch      Default: ios-arm64  (alternatives: ios-arm)
  command   download | install | setup | all (default: all)

Examples:
  $0 <version>                    # download + venv + install on device
  $0 <version> ios-arm64 download # download binary only
  $0 <version> ios-arm64 setup    # download + venv only (no device)
  $0 --list                       # list available versions
EOF
    exit 1
}

[[ -z "${1:-}" ]] && usage

if [[ "$1" == "--list" ]]; then
    require_tools curl jq
    list_versions "${2:-30}"
    exit 0
fi

version="$1"
cmd="${3:-all}"

require_tools curl jq python3

echo "Frida version : ${version}"
echo "Arch          : ${arch}"
echo "Command       : ${cmd}"
echo "( ーoー)o━━☆[[[[Д]]]]ゴーーーン！！"

setup_dirs "${version}"

case "${cmd}" in
    download)
        download_server "${version}" "${arch}"
        ;;
    setup)
        download_server "${version}" "${arch}"
        setup_venv "${version}"
        ;;
    install)
        require_tools iproxy ssh scp
        install_on_device "${version}" "${arch}"
        ;;
    all)
        require_tools iproxy ssh scp
        download_server "${version}" "${arch}"
        setup_venv "${version}"
        install_on_device "${version}" "${arch}"
        ;;
    *)
        die "Unknown command '${cmd}'. Expected: download | setup | install | all"
        ;;
esac

echo ""
echo ":D !!! Done!"
