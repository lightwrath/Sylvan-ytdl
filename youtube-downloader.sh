#!/usr/bin/env bash
# Install and run the YouTube downloader.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
PYTHON="${VENV_DIR}/bin/python"
CONFIG="${SCRIPT_DIR}/channels.json"
APP="${SCRIPT_DIR}/youtube_downloader.py"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

check_ffmpeg() {
    if command -v ffmpeg >/dev/null 2>&1; then
        info "ffmpeg found: $(command -v ffmpeg)"
    else
        warn "ffmpeg was not found. yt-dlp may be unable to merge separate video/audio streams."
        warn "Install it with your OS package manager, for example: sudo apt install ffmpeg"
    fi
}

require_deno_2_3() {
    command -v deno >/dev/null 2>&1 || error "Deno 2.3 or newer is required for the configured PO-token provider"

    local deno_version major minor
    deno_version="$(deno --version 2>/dev/null | awk '$1 == "deno" { print $2; exit }')"
    if [[ ! "${deno_version}" =~ ^([0-9]+)\.([0-9]+) ]]; then
        error "Could not detect the Deno version required for the configured PO-token provider"
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if (( major < 2 || (major == 2 && minor < 3) )); then
        error "Deno ${deno_version} is too old; the configured PO-token provider requires Deno 2.3 or newer"
    fi
}

check_deno() {
    if ! command -v deno >/dev/null 2>&1; then
        warn "Deno was not found. YouTube extraction may have missing formats or fail."
        warn "Install it with your OS package manager, for example: sudo apk add deno"
        return
    fi

    local deno_path deno_version major minor
    deno_path="$(command -v deno)"
    deno_version="$(deno --version 2>/dev/null | awk '$1 == "deno" { print $2; exit }')"
    if [[ "${deno_version}" =~ ^([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        if (( major > 2 || (major == 2 && minor >= 3) )); then
            info "Deno found: ${deno_path} (${deno_version})"
        else
            warn "Deno ${deno_version} is too old; yt-dlp-ejs requires Deno >= 2.3."
            warn "On Alpine 3.20, try: apk add --no-cache --repository https://dl-cdn.alpinelinux.org/alpine/edge/community deno"
        fi
    else
        warn "Deno was found at ${deno_path}, but its version could not be detected."
    fi
}

install_po_provider_if_configured() {
    local provider_home provider_repo
    provider_home="$("${PYTHON}" - "${CONFIG}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    value = json.load(file).get("po_provider_server_home")
if value is not None and not isinstance(value, str):
    raise ValueError("po_provider_server_home must be a string")
print(value or "")
PY
)" || error "Could not read po_provider_server_home from ${CONFIG}"

    # PO-token support is opt-in: it is only installed when this setting exists.
    [[ -n "${provider_home}" ]] || return
    [[ "$(basename -- "${provider_home}")" == "server" ]] \
        || error "po_provider_server_home must be the provider's server directory"
    command -v git >/dev/null 2>&1 || error "git is required for the configured PO-token provider"
    require_deno_2_3

    provider_repo="$(dirname -- "${provider_home}")"
    if [[ ! -d "${provider_repo}" ]]; then
        info "Cloning bgutil PO-token provider into ${provider_repo}"
        mkdir -p "$(dirname -- "${provider_repo}")"
        git clone --depth 1 --branch 1.3.1 \
            https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git "${provider_repo}"
    fi
    [[ -d "${provider_home}" ]] || error "PO-token provider server directory not found: ${provider_home}"

    info "Installing bgutil PO-token provider plugin"
    "${PYTHON}" -m pip install --upgrade bgutil-ytdlp-pot-provider
    info "Installing PO-token provider runtime dependencies"
    (
        cd -- "${provider_home}"
        deno install --allow-scripts=npm:canvas --frozen
    )
}

install_app() {
    command -v python3 >/dev/null 2>&1 || error "python3 is required but was not found"
    [[ -f "${APP}" ]] || error "Application not found: ${APP}"
    [[ -f "${CONFIG}" ]] || error "Configuration not found: ${CONFIG}"
    [[ -f "${SCRIPT_DIR}/requirements.txt" ]] || error "Requirements file not found"

    check_ffmpeg
    check_deno

    if [[ ! -x "${PYTHON}" ]]; then
        info "Creating Python virtual environment in ${VENV_DIR}"
        python3 -m venv "${VENV_DIR}" \
            || error "Could not create the virtual environment. Install your distro's python3-venv package."
    fi

    info "Installing Python dependencies"
    "${PYTHON}" -m pip install --upgrade pip
    # --upgrade ensures an existing deployment receives the current yt-dlp
    # release and its optional EJS challenge-solver distribution.
    "${PYTHON}" -m pip install --upgrade -r "${SCRIPT_DIR}/requirements.txt"
    install_po_provider_if_configured
    info "Setup complete"
}

start_app() {
    if [[ ! -x "${PYTHON}" ]]; then
        info "Virtual environment not found; running setup first"
        install_app
    fi

    [[ -f "${CONFIG}" ]] || error "Configuration not found: ${CONFIG}"
    check_ffmpeg
    check_deno
    info "Starting downloader"
    exec "${PYTHON}" "${APP}" --config "${CONFIG}" "$@"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install       Create the virtual environment and install dependencies
  start         Run one download check (runs install automatically if needed)
  install-start Install dependencies, then run one download check

Examples:
  $(basename "$0") install
  $(basename "$0") start
  $(basename "$0") start --days 14
  $(basename "$0") install-start
EOF
}

command_name="${1:-}"
case "${command_name}" in
    install)
        [[ $# -eq 1 ]] || error "install does not accept arguments"
        install_app
        ;;
    start)
        shift
        start_app "$@"
        ;;
    install-start)
        shift
        install_app
        start_app "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
