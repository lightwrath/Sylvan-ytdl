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

check_deno() {
    if command -v deno >/dev/null 2>&1; then
        info "Deno found: $(command -v deno)"
    else
        warn "Deno was not found. YouTube extraction may have missing formats or fail."
        warn "Install it with your OS package manager, for example: sudo apk add deno"
    fi
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
    "${PYTHON}" -m pip install -r "${SCRIPT_DIR}/requirements.txt"
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
