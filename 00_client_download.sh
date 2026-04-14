#!/bin/bash
set -euo pipefail

trap 'echo "❌ Error on line $LINENO. Exiting."; exit 1' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
OCP_VERSION="${OCP_VERSION:-4.20}"
#https://redhat.enterprise.slack.com/archives/CB95J6R4N/p1775806598928739?thread_ts=1775806598.928739&cid=CB95J6R4N
DOWNLOAD_OPM="${DOWNLOAD_OPM:-false}"
OCP_BASE_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients"
BIN_DIR="./bin"
DOWNLOAD_DIR="${BIN_DIR}/downloads"

if [[ "$OCP_VERSION" =~ -ec\.[0-9]+$ ]]; then
    OCP_URL_PATH="ocp-dev-preview/${OCP_VERSION}"
    IS_DEV_PREVIEW=true
else
    OCP_URL_PATH="ocp/stable-${OCP_VERSION}"
    IS_DEV_PREVIEW=false
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "${RED}❌ Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

RHEL_VERSION=""
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID:-}" == "rhel" ]] || [[ "${ID_LIKE:-}" == *"rhel"* ]] || [[ "${ID_LIKE:-}" == *"fedora"* ]]; then
        if [[ -n "${VERSION_ID:-}" ]]; then
            RHEL_MAJOR_VERSION="${VERSION_ID%%.*}"
            if [[ "$RHEL_MAJOR_VERSION" -ge 9 ]]; then
                RHEL_VERSION="rhel9"
            elif [[ "$RHEL_MAJOR_VERSION" -eq 8 ]]; then
                RHEL_VERSION="rhel8"
            else
                RHEL_VERSION="rhel9"
            fi
        fi
    elif [[ "${ID:-}" == "fedora" ]]; then
        if [[ "${VERSION_ID:-0}" -ge 38 ]]; then
            RHEL_VERSION="rhel9"
        else
            RHEL_VERSION="rhel8"
        fi
    fi
elif [[ -f /etc/redhat-release ]]; then
    if grep -qi "release 9" /etc/redhat-release; then
        RHEL_VERSION="rhel9"
    elif grep -qi "release 8" /etc/redhat-release; then
        RHEL_VERSION="rhel8"
    else
        RHEL_VERSION="rhel9"
    fi
fi

[[ -z "$RHEL_VERSION" ]] && RHEL_VERSION="rhel9"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       OpenShift Client Tools Downloader                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🖥️  System Information:${NC}"
echo -e "${CYAN}   OS: ${OS}${NC}"
echo -e "${CYAN}   Architecture: ${ARCH}${NC}"
echo -e "${CYAN}   RHEL Version: ${RHEL_VERSION}${NC}"
echo -e "${CYAN}   OpenShift Version: ${OCP_VERSION}${NC}"
[[ "$IS_DEV_PREVIEW" == true ]] && echo -e "${CYAN}   Channel: dev-preview${NC}"
echo -e "${CYAN}   Target Directory: ${BIN_DIR}${NC}"
echo ""

command_exists() { command -v "$1" >/dev/null 2>&1; }

download_oc() {
    local download_url="${OCP_BASE_URL}/${OCP_URL_PATH}/openshift-client-${OS}-${ARCH}-${RHEL_VERSION}.tar.gz"
    local temp_file="${DOWNLOAD_DIR}/openshift-client.tar.gz"

    echo -e "${BLUE}📥 Downloading oc client...${NC}"
    echo -e "${YELLOW}   URL: ${download_url}${NC}"

    curl -L --fail --progress-bar "${download_url}" -o "${temp_file}"

    echo -e "${BLUE}📦 Extracting oc client...${NC}"
    tar -xzf "${temp_file}" -C "${BIN_DIR}" oc
    chmod +x "${BIN_DIR}/oc"

    echo -e "${GREEN}✅ oc installed${NC}"
    rm -f "${temp_file}"
}

_cleanup_opm_extract_artifacts() {
    rm -f "${DOWNLOAD_DIR}/opm"* 2>/dev/null || true
}

_extract_and_install_opm() {
    local temp_file="${DOWNLOAD_DIR}/opm.tar.gz"

    _cleanup_opm_extract_artifacts
    tar -xzf "${temp_file}" -C "${DOWNLOAD_DIR}"

    local opm_binary=""
    for f in opm opm-${RHEL_VERSION} opm-rhel9 opm-rhel8; do
        [[ -f "${DOWNLOAD_DIR}/$f" ]] && opm_binary="${DOWNLOAD_DIR}/$f"
    done

    [[ -z "$opm_binary" ]] && return 1

    mv "$opm_binary" "${BIN_DIR}/opm"
    chmod +x "${BIN_DIR}/opm"
    rm -f "${temp_file}"

    echo -e "${GREEN}✅ opm installed${NC}"
}

download_opm() {
    local base="${OCP_BASE_URL}/${OCP_URL_PATH}"
    local temp_file="${DOWNLOAD_DIR}/opm.tar.gz"

    for url in \
        "${base}/opm-${OS}-${RHEL_VERSION}.tar.gz" \
        "${base}/opm-${OS}-${OCP_VERSION}.tar.gz"
    do
        echo -e "${YELLOW}Trying: $url${NC}"
        if curl -L --fail --progress-bar "$url" -o "$temp_file"; then
            _extract_and_install_opm && return 0
        fi
    done

    return 1
}

download_oc_mirror() {
    local url="${OCP_BASE_URL}/${OCP_URL_PATH}/oc-mirror.tar.gz"
    local temp_file="${DOWNLOAD_DIR}/oc-mirror.tar.gz"

    curl -L --fail --progress-bar "$url" -o "$temp_file"
    tar -xzf "$temp_file" -C "${DOWNLOAD_DIR}"

    local bin=""
    for f in oc-mirror oc-mirror-${RHEL_VERSION} oc-mirror-rhel9 oc-mirror-rhel8; do
        [[ -f "${DOWNLOAD_DIR}/$f" ]] && bin="${DOWNLOAD_DIR}/$f"
    done

    [[ -z "$bin" ]] && return 1

    mv "$bin" "${BIN_DIR}/oc-mirror"
    chmod +x "${BIN_DIR}/oc-mirror"
    rm -f "$temp_file"

    echo -e "${GREEN}✅ oc-mirror installed${NC}"
}

check_existing_tool() {
    local tool="$1"
    [[ -x "${BIN_DIR}/${tool}" ]] || return 0

    echo -e "${YELLOW}${tool} exists. Overwrite? (y/N)${NC}"
    read -r r
    [[ "$r" =~ ^[Yy]$ ]]
}

main() {
    mkdir -p "$BIN_DIR" "$DOWNLOAD_DIR"

    command_exists curl || { echo "curl missing"; exit 1; }
    command_exists tar || { echo "tar missing"; exit 1; }

    local oc_success=false
    local opm_success=false
    local oc_mirror_success=false

    echo "---- oc ----"
    if check_existing_tool oc; then
        download_oc && oc_success=true
    else
        oc_success=true
    fi

    echo "---- opm ----"
    if [[ "$DOWNLOAD_OPM" == "true" ]]; then
        if check_existing_tool opm; then
            download_opm && opm_success=true
        else
            opm_success=true
        fi
    else
        echo -e "${YELLOW}Skipping opm (disabled)${NC}"
        opm_success=true
    fi

    echo "---- oc-mirror ----"
    if check_existing_tool oc-mirror; then
        download_oc_mirror && oc_mirror_success=true
    else
        oc_mirror_success=true
    fi

    rm -rf "$DOWNLOAD_DIR"

    echo ""
    echo "Summary:"
    echo "oc: $oc_success"
    echo "opm: $opm_success"
    echo "oc-mirror: $oc_mirror_success"
}

main "$@"