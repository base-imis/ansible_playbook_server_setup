#!/usr/bin/env bash

set -Eeuo pipefail

# Run this script from any directory. All files are resolved relative to the
# directory containing this script so the manifest and icons stay together.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required but was not found in PATH." >&2
    exit 1
fi

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    echo "Creating virtual environment: ${VENV_DIR}"
    if ! python3 -m venv "${VENV_DIR}"; then
        echo "Python's venv/pip support is missing. Installing Debian/Ubuntu prerequisites..." >&2
        rm -rf "${VENV_DIR}"

        if ! command -v apt-get >/dev/null 2>&1; then
            echo "Install Python venv and pip support manually, then rerun this script:" >&2
            echo "  sudo apt update" >&2
            echo "  sudo apt install -y python3-venv python3-pip" >&2
            exit 1
        fi

        if [[ "${EUID}" -eq 0 ]]; then
            APT_PREFIX=()
        elif command -v sudo >/dev/null 2>&1; then
            APT_PREFIX=(sudo)
        else
            echo "sudo is required to install Python venv and pip support." >&2
            echo "Run these commands manually, then rerun this script:" >&2
            echo "  sudo apt update" >&2
            echo "  sudo apt install -y python3-venv python3-pip" >&2
            exit 1
        fi

        "${APT_PREFIX[@]}" apt-get update
        "${APT_PREFIX[@]}" apt-get install -y python3-venv python3-pip
        python3 -m venv "${VENV_DIR}"
    fi
fi

PYTHON="${VENV_DIR}/bin/python"

if ! "${PYTHON}" -m pip --version >/dev/null 2>&1; then
    echo "The virtual environment has no pip. Recreate it after installing python3-venv." >&2
    echo "  sudo apt update" >&2
    echo "  sudo apt install -y python3-venv python3-pip" >&2
    exit 1
fi

echo "Installing/updating Python requirements..."
"${PYTHON}" -m pip install --requirement "${SCRIPT_DIR}/requirements.txt"

if [[ ! -f "${SCRIPT_DIR}/create_workspace_from_manifest.py" ]]; then
    echo "Error: create_workspace_from_manifest.py was not found." >&2
    exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/icons" ]]; then
    echo "Warning: icons directory was not found. Styles requiring icons may fail." >&2
fi

# Manifests contain database credentials. Restrict access when the default
# manifest is present. The importer can still be given a different manifest.
DEFAULT_MANIFEST="${SCRIPT_DIR}/imis_base_source_configuration.json"
if [[ -f "${DEFAULT_MANIFEST}" ]]; then
    chmod 600 "${DEFAULT_MANIFEST}"
    echo "Restricted permissions on ${DEFAULT_MANIFEST}"
fi

echo "Starting GeoServer workspace importer..."
exec "${PYTHON}" "${SCRIPT_DIR}/create_workspace_from_manifest.py" "$@"
