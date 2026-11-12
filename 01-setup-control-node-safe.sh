#!/usr/bin/env bash

set -Eeuo pipefail

readonly REQUIRED_PACKAGES=(
    ansible
    python3
    python3-pip
    git
    openssh-client
    sudo
)

readonly DEFAULT_REPOSITORY_URL="https://github.com/InSol-2021/server-setup-ansible.git"

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

echo "=================================================="
echo " Safe Ansible Control Node Setup"
echo "=================================================="

# --------------------------------------------------
# 1. Basic pre-flight checks
# --------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    error "Run this script as root, for example: sudo ./01-setup-control-node-safe.sh"
fi

if [[ ! -r /etc/os-release ]]; then
    error "Cannot identify the operating system."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *debian* ]]; then
    error "This script requires Ubuntu or Debian. Detected: ${PRETTY_NAME:-unknown}"
fi

if ! command -v apt-get >/dev/null 2>&1; then
    error "apt-get is not available."
fi

if ! command -v dpkg >/dev/null 2>&1; then
    error "dpkg is not available."
fi

echo "[OK] Operating system: ${PRETTY_NAME:-unknown}"
echo "[OK] Running as root."

if command -v fuser >/dev/null 2>&1 && fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; then
    error "Another package-manager process is running. Wait for it to finish and try again."
fi

if ! command -v df >/dev/null 2>&1; then
    error "The df command is not available."
fi

available_kb="$(df --output=avail / | tail -n 1 | tr -d ' ')"
if [[ ! "${available_kb}" =~ ^[0-9]+$ ]] || (( available_kb < 1048576 )); then
    error "At least 1 GiB of free space is recommended on /."
fi

echo "[OK] Free space on /: $((available_kb / 1024)) MiB"

# Never start an update while dpkg is already broken. `dpkg --audit` can
# report problems while still returning exit status 0, so inspect its output.
dpkg_audit="$(dpkg --audit)"
if [[ -n "${dpkg_audit}" ]]; then
    echo "${dpkg_audit}" >&2
    error "dpkg reports an incomplete package installation. Repair it before continuing."
fi

if ! apt-get check; then
    error "APT reports broken dependencies. Repair them before continuing."
fi

# --------------------------------------------------
# 2. Detect the GRUB failure seen during the previous upgrade
# --------------------------------------------------
if command -v debconf-show >/dev/null 2>&1 && dpkg-query -W -f='${db:Status-Status}' grub-pc 2>/dev/null | grep -q '^installed$'; then
    echo ""
    echo ">>> Checking the configured GRUB installation devices..."

    grub_devices="$(debconf-show grub-pc 2>/dev/null | sed -n 's/^ grub-pc\/install_devices:[[:space:]]*//p')"
    if [[ -n "${grub_devices}" ]]; then
        while IFS= read -r device; do
            [[ -z "${device}" ]] && continue
            if [[ ! -e "${device}" ]]; then
                error "GRUB references missing device: ${device}. Verify the boot disk before upgrading."
            fi
        done < <(tr ',' '\n' <<< "${grub_devices}" | sed 's/^ *//;s/ *$//')
    fi
fi

# --------------------------------------------------
# 3. Refresh package information
# --------------------------------------------------
echo ""
echo ">>> Updating package information..."
apt-get update

# A full distribution upgrade is not required to install the control-node tools.
# Offer it separately and keep it interactive so GRUB/configuration prompts are visible.
echo ""
read -r -p "Upgrade all currently installed packages now? [y/N] " upgrade_choice
if [[ "${upgrade_choice}" =~ ^[Yy]$ ]]; then
    echo ">>> Upgrading installed packages..."
    apt-get upgrade
else
    echo "[INFO] Skipping full system upgrade."
fi

# --------------------------------------------------
# 4. Install only the control-node requirements
# --------------------------------------------------
echo ""
echo ">>> Installing required control-node packages..."
apt-get install -y "${REQUIRED_PACKAGES[@]}"

# --------------------------------------------------
# 5. Verify installed tools
# --------------------------------------------------
echo ""
echo ">>> Checking installed versions..."
echo ""
echo "Ansible:"
ansible --version | head -n 1
echo ""
echo "Python:"
python3 --version
echo ""
echo "Git:"
git --version

# --------------------------------------------------
# 6. Clone the deployment repository after Git is installed
# --------------------------------------------------
echo ""
echo ">>> Getting the deployment repository..."

repository_url="${DEPLOYMENT_REPOSITORY_URL:-${DEFAULT_REPOSITORY_URL}}"
read -r -p "Deployment repository URL [${repository_url}]: " repository_url_input
repository_url="${repository_url_input:-${repository_url}}"

control_user="${SUDO_USER:-root}"
control_home="$(getent passwd "${control_user}" | cut -d: -f6)"
control_home="${control_home:-/root}"
default_repository_dir="${control_home}/server-setup-ansible"
read -r -p "Repository directory [${default_repository_dir}]: " repository_dir_input
repository_dir="${repository_dir_input:-${default_repository_dir}}"

if [[ -e "${repository_dir}" ]]; then
    if [[ -d "${repository_dir}/.git" ]]; then
        echo "[INFO] Repository already exists at ${repository_dir}; leaving it unchanged."
    else
        error "The repository directory exists but is not a Git repository: ${repository_dir}"
    fi
else
    parent_dir="$(dirname "${repository_dir}")"
    install -d -m 0755 "${parent_dir}"
    git clone "${repository_url}" "${repository_dir}"
    if [[ "${control_user}" != "root" ]]; then
        control_group="$(id -gn "${control_user}")"
        chown -R "${control_user}:${control_group}" "${repository_dir}"
    fi
    echo "[OK] Repository cloned to ${repository_dir}"
fi

# --------------------------------------------------
# 7. Run safe local checks without requiring inventory changes
# --------------------------------------------------
echo ""
echo ">>> Running local control-node checks..."
ansible localhost -c local -m ansible.builtin.command -a "whoami"
ansible localhost -c local -m ansible.builtin.command -a "hostname"
ansible localhost -c local -m ansible.builtin.command -a "uptime"
ansible localhost -c local -m ansible.builtin.command -a "df -h /"
ansible localhost -c local -m ansible.builtin.command -a "free -h"

echo ""
echo "=================================================="
echo " Safe Ansible control-node setup completed"
echo "=================================================="
echo ""
echo "Repository: ${repository_dir}"
echo "Next step: cd ${repository_dir} and run 02-ssh.sh to configure SSH keys."
