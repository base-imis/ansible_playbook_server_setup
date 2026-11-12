#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SSH_DIR="/root/.ssh"
PRIVATE_KEY="$SSH_DIR/id_ed25519_ansible"
PUBLIC_KEY="$PRIVATE_KEY.pub"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

log() {
    printf '%s\n' "$*"
}

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

fix_ssh_permissions() {
    log '>>> Correcting SSH ownership and permissions...'

    install -d \
        -m 0700 \
        -o root \
        -g root \
        "$SSH_DIR"

    if [[ -f "$PRIVATE_KEY" ]]; then
        chown root:root "$PRIVATE_KEY"
        chmod 0600 "$PRIVATE_KEY"
    fi

    if [[ -f "$PUBLIC_KEY" ]]; then
        chown root:root "$PUBLIC_KEY"
        chmod 0644 "$PUBLIC_KEY"
    fi

    if [[ -f "$AUTHORIZED_KEYS" ]]; then
        chown root:root "$AUTHORIZED_KEYS"
        chmod 0600 "$AUTHORIZED_KEYS"
    fi
}

add_authorized_key() {
    local key_line="$1"
    local temp_key

    key_line="${key_line%$'\r'}"

    if [[ -z "${key_line//[[:space:]]/}" ]]; then
        return 0
    fi

    if [[ "$key_line" == \#* ]]; then
        return 0
    fi

    if [[ "$key_line" == *"PRIVATE KEY"* ]]; then
        printf '[ERROR] A private key was supplied. Only add a public key.\n' >&2
        return 1
    fi

    temp_key="$(mktemp)"
    printf '%s\n' "$key_line" > "$temp_key"

    if ! ssh-keygen -l -f "$temp_key" >/dev/null 2>&1; then
        rm -f "$temp_key"
        printf '[ERROR] The supplied value is not a valid OpenSSH public key.\n' >&2
        return 1
    fi

    rm -f "$temp_key"

    if grep -Fqx -- "$key_line" "$AUTHORIZED_KEYS"; then
        log '[OK] Public key already exists in authorized_keys; duplicate not added.'
        return 0
    fi

    printf '%s\n' "$key_line" >> "$AUTHORIZED_KEYS"

    chown root:root "$AUTHORIZED_KEYS"
    chmod 0600 "$AUTHORIZED_KEYS"

    log '[OK] Public key added to /root/.ssh/authorized_keys.'
}

add_key_from_input() {
    local supplied_value="$1"
    local key_line
    local added=0

    if [[ -f "$supplied_value" ]]; then

        while IFS= read -r key_line || [[ -n "$key_line" ]]; do

            if [[ -z "${key_line//[[:space:]]/}" ]]; then
                continue
            fi

            if [[ "$key_line" == \#* ]]; then
                continue
            fi

            add_authorized_key "$key_line"
            added=1

        done < "$supplied_value"

        if [[ "$added" -eq 0 ]]; then
            printf '[ERROR] No public SSH key was found in: %s\n' \
                "$supplied_value" >&2
            return 1
        fi

    else
        add_authorized_key "$supplied_value"
    fi
}

# ================================================================
# Root requirement
# ================================================================

if [[ "$EUID" -ne 0 ]]; then
    fail 'Run this script on the control server as root: sudo ./02-create-initial-managed-user.sh'
fi

# ================================================================
# Required command
# ================================================================

command -v ssh-keygen >/dev/null 2>&1 || \
    fail 'ssh-keygen is not installed. Run 01-setup-control-node.sh first.'

log '=================================================='
log ' Control Server SSH Setup'
log '=================================================='
log ''
log 'This script prepares SSH files for root on this control server.'
log 'It does not connect to or modify a managed server.'
log ''

# ================================================================
# Create SSH directory
# ================================================================

log '>>> Creating /root/.ssh with secure permissions...'

install -d \
    -m 0700 \
    -o root \
    -g root \
    "$SSH_DIR"

# ================================================================
# authorized_keys
# ================================================================

log '>>> Creating or preserving /root/.ssh/authorized_keys...'

touch "$AUTHORIZED_KEYS"

chown root:root "$AUTHORIZED_KEYS"
chmod 0600 "$AUTHORIZED_KEYS"

# ================================================================
# SSH key pair
# ================================================================

if [[ -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then

    log "[OK] Existing Ansible SSH key pair found:"
    log "     $PRIVATE_KEY"

elif [[ -f "$PRIVATE_KEY" && ! -f "$PUBLIC_KEY" ]]; then

    log '[WARN] Private key exists but public key is missing.'
    log '>>> Recreating public key from existing private key...'

    ssh-keygen \
        -y \
        -f "$PRIVATE_KEY" \
        > "$PUBLIC_KEY"

    log "[OK] Public key recreated: $PUBLIC_KEY"

elif [[ ! -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then

    fail "Public key exists but private key is missing: $PRIVATE_KEY"

else

    log '>>> Generating dedicated Ed25519 SSH key pair for Ansible...'

    ssh-keygen \
        -t ed25519 \
        -a 100 \
        -N '' \
        -f "$PRIVATE_KEY" \
        -C "ansible-root-control@$(hostname)"

    log '[OK] SSH key pair generated.'

fi

# ================================================================
# Correct ownership + permissions after key creation
# ================================================================

fix_ssh_permissions

# ================================================================
# Verify files
# ================================================================

log ''
log '>>> Verifying generated SSH files...'

[[ -s "$PRIVATE_KEY" ]] || \
    fail "Private key is missing or empty: $PRIVATE_KEY"

[[ -s "$PUBLIC_KEY" ]] || \
    fail "Public key is missing or empty: $PUBLIC_KEY"

[[ -f "$AUTHORIZED_KEYS" ]] || \
    fail "authorized_keys was not created: $AUTHORIZED_KEYS"

if ! ssh-keygen -y -f "$PRIVATE_KEY" >/dev/null 2>&1; then
    fail 'The private key could not be validated.'
fi

if ! ssh-keygen -l -f "$PUBLIC_KEY" >/dev/null 2>&1; then
    fail 'The public key could not be validated.'
fi

log '[OK] Private and public SSH keys are valid.'

# ================================================================
# Optional authorized_keys additions
# ================================================================

log ''

read -r -p \
    'Do you want to add a public SSH key to /root/.ssh/authorized_keys now? [y/N]: ' \
    ADD_KEY_REPLY

while [[ "$ADD_KEY_REPLY" =~ ^[Yy]$ ]]; do

    log ''
    log 'Paste one complete public SSH key, or enter the path to a public-key file.'
    log 'Example file: /root/user-key.pub'

    read -r -p 'Public key or file path: ' KEY_INPUT

    if [[ -z "${KEY_INPUT//[[:space:]]/}" ]]; then

        log '[INFO] Nothing was entered; no key was added.'

    else

        add_key_from_input "$KEY_INPUT"

    fi

    # Correct permissions again after modification.
    fix_ssh_permissions

    log ''

    read -r -p \
        'Add another public SSH key? [y/N]: ' \
        ADD_KEY_REPLY

done

# ================================================================
# Final permissions
# ================================================================

fix_ssh_permissions

# ================================================================
# Final verification
# ================================================================

log ''
log '>>> Final permissions:'
log ''

ls -ld "$SSH_DIR"
ls -l "$PRIVATE_KEY"
ls -l "$PUBLIC_KEY"
ls -l "$AUTHORIZED_KEYS"

log ''
log 'Expected permissions:'
log '  /root/.ssh                         drwx------  (700)'
log '  id_ed25519_ansible                 -rw-------  (600)'
log '  id_ed25519_ansible.pub             -rw-r--r--  (644)'
log '  authorized_keys                    -rw-------  (600)'

log ''
log '=================================================='
log ' Control server SSH setup completed'
log '=================================================='
log ''

log 'Created or preserved:'
log "  $PRIVATE_KEY"
log "  $PUBLIC_KEY"
log "  $AUTHORIZED_KEYS"

log ''
log 'Directory structure:'
log '  /root/.ssh/'
log '  |-- id_ed25519_ansible'
log '  |-- id_ed25519_ansible.pub'
log '  `-- authorized_keys'

log ''
log 'IMPORTANT:'
log '  The PRIVATE key stays on this control server.'
log '  Only the PUBLIC key should be placed on managed servers.'

log ''
log 'Generated/current public key:'
cat "$PUBLIC_KEY"
