#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="zig-foundry"
REPO_NAME="zig-analyzer"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
DEFAULT_PREFIX="${HOME}/.local/bin"
PREFIX="${DEFAULT_PREFIX}"
OPTIMIZE="ReleaseFast"
MODE="release" # Options: release, dev, local, github, uninstall
TEMP_DIR=""

# Color formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { printf "${BLUE}${BOLD}[INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}${BOLD}[OK]${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}${BOLD}[WARN]${NC} %s\n" "$1"; }
log_error()   { printf "${RED}${BOLD}[ERROR]${NC} %s\n" "$1" >&2; }

cleanup() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

show_help() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Default:
  Downloads and installs the latest stable prebuilt binary from GitHub.

Options:
  --dev                Download prebuilt development build (built on push to main)
  --local              Build and install directly from current directory source
  --github             Perform a shallow clone in a temporary folder, build, and remove source
  --uninstall          Remove the installed zig-analyzer binary
  --prefix <DIR>       Installation directory (default: ~/.local/bin)
  --optimize <MODE>    Zig optimization mode: ReleaseFast, ReleaseSafe, Debug (default: ReleaseFast)
  -h, --help           Show this message
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev)
            MODE="dev"
            shift
            ;;
        --local)
            MODE="local"
            shift
            ;;
        --github)
            MODE="github"
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --optimize)
            OPTIMIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Downloader helper
DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
fi

fetch_url() {
    local url="$1"
    local output="$2"
    if [[ "${DOWNLOADER}" == "curl" ]]; then
        curl -sSfL "${url}" -o "${output}"
    elif [[ "${DOWNLOADER}" == "wget" ]]; then
        wget -q -O "${output}" "${url}"
    else
        log_error "curl or wget is required."
        exit 1
    fi
}

fetch_text() {
    local url="$1"
    if [[ "${DOWNLOADER}" == "curl" ]]; then
        curl -sSfL "${url}"
    elif [[ "${DOWNLOADER}" == "wget" ]]; then
        wget -q -O - "${url}"
    else
        log_error "curl or wget is required."
        exit 1
    fi
}

detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "${arch}" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *)
            log_error "Unsupported architecture: ${arch}"
            exit 1
            ;;
    esac

    case "${os}" in
        linux*)  os="linux" ;;
        darwin*) os="macos" ;;
        msys*|cygwin*|mingw*) os="windows" ;;
        *)
            log_error "Unsupported operating system: ${os}"
            exit 1
            ;;
    esac

    echo "${arch}-${os}"
}

# --- Action 1: Uninstall ---
uninstall_binary() {
    local target="${PREFIX}/zig-analyzer"
    local target_exe="${PREFIX}/zig-analyzer.exe"
    local removed=false

    log_info "Looking for installations to remove..."

    if [[ -f "${target}" ]]; then
        rm -f "${target}"
        log_success "Removed ${target}"
        removed=true
    fi

    if [[ -f "${target_exe}" ]]; then
        rm -f "${target_exe}"
        log_success "Removed ${target_exe}"
        removed=true
    fi

    if [[ "${removed}" == false ]]; then
        log_warn "No binary found in ${PREFIX}."
    fi

    if command -v zig-analyzer >/dev/null 2>&1; then
        local other_loc
        other_loc="$(command -v zig-analyzer)"
        log_warn "Another binary is still present in PATH at: ${other_loc}"
    fi

    log_success "Uninstall completed."
    exit 0
}

# --- Action 2: Download Release / Dev Binary ---
install_prebuilt() {
    if [[ -z "${DOWNLOADER}" ]]; then
        log_error "curl or wget is required to download prebuilt releases."
        exit 1
    fi

    local target_platform
    target_platform="$(detect_platform)"
    log_info "Detected target platform: ${target_platform}"

    local ext="tar.gz"
    [[ "${target_platform}" == *"windows"* ]] && ext="zip"
    local asset_name="zig-analyzer-${target_platform}.${ext}"

    local download_url=""
    if [[ "${MODE}" == "dev" ]]; then
        log_info "Downloading latest development build..."
        download_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/dev/${asset_name}"
    else
        log_info "Querying latest stable release from GitHub..."
        local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
        local release_json
        release_json="$(fetch_text "${api_url}" 2>/dev/null || true)"

        if [[ -z "${release_json}" || "${release_json}" == *"Not Found"* ]]; then
            log_error "No stable release found for ${REPO_OWNER}/${REPO_NAME}."
            log_info "You can use the dev build instead:"
            log_info "  ./install.sh --dev"
            log_info "Or compile from source:"
            log_info "  ./install.sh --local"
            exit 1
        fi

        download_url="$(echo "${release_json}" | grep -o "https://[^\"]*${asset_name}" | head -n 1 || true)"
    fi

    if [[ -z "${download_url}" ]]; then
        log_error "Could not find asset '${asset_name}' for this release."
        exit 1
    fi

    TEMP_DIR=$(mktemp -d)
    local archive_path="${TEMP_DIR}/${asset_name}"

    log_info "Downloading ${asset_name}..."
    if ! fetch_url "${download_url}" "${archive_path}"; then
        echo ""
        if [[ "${MODE}" == "dev" ]]; then
            log_error "Failed to download development asset."
            log_info "Ensure CI has completed on the 'main' branch to generate the 'dev' release."
        else
            log_error "Failed to download release asset."
        fi
        exit 1
    fi

    log_info "Extracting..."
    mkdir -p "${TEMP_DIR}/out"
    if [[ "${ext}" == "tar.gz" ]]; then
        tar -xzf "${archive_path}" -C "${TEMP_DIR}/out"
    else
        unzip -q "${archive_path}" -d "${TEMP_DIR}/out"
    fi

    local bin_source="${TEMP_DIR}/out/zig-analyzer"
    [[ "${target_platform}" == *"windows"* ]] && bin_source="${TEMP_DIR}/out/zig-analyzer.exe"

    if [[ ! -f "${bin_source}" ]]; then
        log_error "Binary not found inside the downloaded archive."
        exit 1
    fi

    mkdir -p "${PREFIX}"
    install -m 755 "${bin_source}" "${PREFIX}/zig-analyzer"
    log_success "Successfully installed binary to ${PREFIX}/zig-analyzer"
}

# --- Action 3: Shallow Clone & Build in Temp Directory (--github) ---
install_github_build() {
    if ! command -v zig >/dev/null 2>&1; then
        log_error "Zig is required to compile. Please install Zig first."
        exit 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is required for cloning."
        exit 1
    fi

    TEMP_DIR=$(mktemp -d)
    local clone_dir="${TEMP_DIR}/repo"

    log_info "Fetching shallow clone of ${REPO_URL} into temporary storage..."
    git clone --depth 1 --shallow-submodules --recurse-submodules "${REPO_URL}" "${clone_dir}"

    cd "${clone_dir}"
    log_info "Compiling zig-analyzer (-Doptimize=${OPTIMIZE})..."
    zig build -Doptimize="${OPTIMIZE}"

    local out_bin=""
    if [[ -f "zig-out/bin/zig-analyzer" ]]; then
        out_bin="zig-out/bin/zig-analyzer"
    elif [[ -f "zig-out/bin/zig_analyzer" ]]; then
        out_bin="zig-out/bin/zig_analyzer"
    fi

    if [[ -z "${out_bin}" || ! -f "${out_bin}" ]]; then
        log_error "Could not locate compiled binary in zig-out/bin/"
        exit 1
    fi

    mkdir -p "${PREFIX}"
    install -m 755 "${out_bin}" "${PREFIX}/zig-analyzer"
    log_success "Installed binary to ${PREFIX}/zig-analyzer"
    log_info "Cleaning up temporary source files..."
}

# --- Action 4: Build From Local Directory (--local) ---
install_local() {
    if ! command -v zig >/dev/null 2>&1; then
        log_error "Zig is required to compile."
        exit 1
    fi

    if [[ ! -f "build.zig" ]]; then
        log_error "No build.zig found in the current working directory."
        exit 1
    fi

    log_info "Updating submodules..."
    git submodule update --init --recursive --quiet || true

    log_info "Compiling zig-analyzer (-Doptimize=${OPTIMIZE})..."
    zig build -Doptimize="${OPTIMIZE}"

    local out_bin=""
    if [[ -f "zig-out/bin/zig-analyzer" ]]; then
        out_bin="zig-out/bin/zig-analyzer"
    elif [[ -f "zig-out/bin/zig_analyzer" ]]; then
        out_bin="zig-out/bin/zig_analyzer"
    fi

    if [[ -z "${out_bin}" || ! -f "${out_bin}" ]]; then
        log_error "Could not locate compiled binary in zig-out/bin/"
        exit 1
    fi

    mkdir -p "${PREFIX}"
    install -m 755 "${out_bin}" "${PREFIX}/zig-analyzer"
    log_success "Installed binary to ${PREFIX}/zig-analyzer"
}

# --- Main Dispatch ---
if [[ "${MODE}" == "uninstall" ]]; then
    uninstall_binary
fi

# Check for existing binary
TARGET_BIN="${PREFIX}/zig-analyzer"
if command -v zig-analyzer >/dev/null 2>&1; then
    log_warn "Existing zig-analyzer found at: $(command -v zig-analyzer)"
fi

case "${MODE}" in
    release|dev) install_prebuilt ;;
    github)      install_github_build ;;
    local)       install_local ;;
esac

# PATH Verification
case ":${PATH}:" in
    *:"${PREFIX}":*) ;;
    *)
        log_warn "${PREFIX} is not in your current PATH."
        echo "Add it to your shell profile (~/.bashrc or ~/.zshrc):"
        echo "  export PATH=\"${PREFIX}:\$PATH\""
        ;;
esac

echo ""
printf "${GREEN}${BOLD}Done! Run zig-analyzer to get started.${NC}\n"
