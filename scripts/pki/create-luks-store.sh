#!/usr/bin/env bash
# =============================================================================
# create-luks-store.sh - Simulated offline/HSM key storage using LUKS
# =============================================================================
#
# PURPOSE:
#   In production, the Root CA private key lives in an HSM (Hardware Security
#   Module) or an offline, air-gapped system. We simulate this with a LUKS-
#   encrypted loopback device. The key only exists in cleartext when:
#     1. The LUKS volume is explicitly opened with a passphrase
#     2. The device is mounted to a known path
#
#   This teaches the LUKS workflow relevant to:
#     - NIST 800-53 SC-28 (Protection of Information at Rest)
#     - Government FDE requirements for removable media
#     - Key custodian procedures in PKI operations
#
# WHAT THIS CREATES:
#   pki/root-ca-store.luks   - 50MB encrypted loopback file (the "offline drive")
#
# OPERATIONS:
#   ./scripts/pki/create-luks-store.sh create   - Create and initialise the store
#   ./scripts/pki/create-luks-store.sh open      - Decrypt and mount (to access key)
#   ./scripts/pki/create-luks-store.sh close     - Unmount and lock the store
#   ./scripts/pki/create-luks-store.sh status    - Show whether store is open or closed
#
# USAGE PATTERN (simulating offline CA operations):
#   1. open   — mount the encrypted store (requires passphrase)
#   2. use root CA key from /mnt/gateway-ca-store/ to sign intermediate CSRs
#   3. close  — unmount and lock immediately after use
#
# REQUIREMENTS:
#   - cryptsetup (dnf install cryptsetup)
#   - Must run as root (LUKS operations require root)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PKI_DIR="${PROJECT_ROOT}/pki"
STORE_FILE="${PKI_DIR}/root-ca-store.luks"
MAPPER_NAME="gateway-ca-store"
MOUNT_POINT="/mnt/${MAPPER_NAME}"
STORE_SIZE_MB=50

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This operation requires root. Run with: sudo $0 $*"
        exit 1
    fi
}

require_cryptsetup() {
    if ! command -v cryptsetup &>/dev/null; then
        log_error "cryptsetup is not installed. Install with: dnf install cryptsetup"
        exit 1
    fi
}

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  create   Create and initialise a new encrypted LUKS store
  open     Decrypt and mount the store (type passphrase when prompted)
  close    Unmount and lock the store
  status   Show whether the store is currently open or closed

Example workflow:
  sudo $0 create             # First time only
  sudo $0 open               # Before signing a certificate
  # ... use key at ${MOUNT_POINT}/private/root-ca.key ...
  sudo $0 close              # Immediately after use
EOF
    exit 1
}

# ---------------------------------------------------------------------------
# create: make the LUKS loopback file
# ---------------------------------------------------------------------------
cmd_create() {
    require_root
    require_cryptsetup

    if [[ -f "${STORE_FILE}" ]]; then
        log_warn "Store already exists at: ${STORE_FILE}"
        read -rp "Destroy and recreate? (type 'yes' to confirm): " CONFIRM
        [[ "${CONFIRM}" == "yes" ]] || { log_info "Aborted."; exit 0; }
        rm -f "${STORE_FILE}"
    fi

    mkdir -p "${PKI_DIR}"

    log_info "Creating ${STORE_SIZE_MB}MB loopback file..."
    # dd if=/dev/urandom gives us a pre-randomised file, which:
    #   a) makes LUKS metadata analysis harder (no pattern to distinguish used from unused)
    #   b) demonstrates the secure erasure concept for decommissioning
    dd if=/dev/urandom of="${STORE_FILE}" bs=1M count="${STORE_SIZE_MB}" status=progress
    chmod 600 "${STORE_FILE}"

    log_info "Formatting with LUKS2..."
    # LUKS2 is the current standard. Key derivation uses Argon2id (memory-hard,
    # GPU-resistant), which is stronger than LUKS1's PBKDF2.
    # --batch-mode suppresses the "are you sure?" prompt (we already confirmed above).
    cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha256 \
        --pbkdf argon2id \
        "${STORE_FILE}"

    log_info "Opening for initial setup..."
    cryptsetup open "${STORE_FILE}" "${MAPPER_NAME}"

    log_info "Creating ext4 filesystem inside LUKS container..."
    mkfs.ext4 -L "gateway-ca-store" "/dev/mapper/${MAPPER_NAME}" -q

    log_info "Mounting at ${MOUNT_POINT}..."
    mkdir -p "${MOUNT_POINT}"
    mount "/dev/mapper/${MAPPER_NAME}" "${MOUNT_POINT}"

    log_info "Creating directory structure for Root CA key..."
    mkdir -p "${MOUNT_POINT}/private"
    chmod 700 "${MOUNT_POINT}/private"

    log_info "Moving Root CA private key into encrypted store..."
    if [[ -f "${PKI_DIR}/root-ca/private/root-ca.key" ]]; then
        mv "${PKI_DIR}/root-ca/private/root-ca.key" "${MOUNT_POINT}/private/root-ca.key"
        chmod 400 "${MOUNT_POINT}/private/root-ca.key"
        log_info "Root CA key moved to encrypted store."
    else
        log_warn "Root CA key not found at ${PKI_DIR}/root-ca/private/root-ca.key"
        log_warn "Run create-root-ca.sh first, then re-run this script."
    fi

    log_info "Unmounting and closing..."
    umount "${MOUNT_POINT}"
    cryptsetup close "${MAPPER_NAME}"

    log_info "============================================="
    log_info "LUKS store created and closed."
    log_info "Store file: ${STORE_FILE}"
    log_info ""
    log_info "The Root CA private key is now encrypted at rest."
    log_info "To sign a certificate: sudo $0 open"
    log_info "After signing:         sudo $0 close"
    log_info "============================================="
}

# ---------------------------------------------------------------------------
# open: decrypt and mount
# ---------------------------------------------------------------------------
cmd_open() {
    require_root
    require_cryptsetup

    if [[ ! -f "${STORE_FILE}" ]]; then
        log_error "Store not found at ${STORE_FILE}. Run: sudo $0 create"
        exit 1
    fi

    if cryptsetup status "${MAPPER_NAME}" &>/dev/null; then
        log_warn "Store is already open at ${MOUNT_POINT}"
        exit 0
    fi

    log_info "Opening LUKS container (passphrase required)..."
    cryptsetup open "${STORE_FILE}" "${MAPPER_NAME}"

    mkdir -p "${MOUNT_POINT}"
    mount "/dev/mapper/${MAPPER_NAME}" "${MOUNT_POINT}"

    log_info "Store open. Root CA key available at: ${MOUNT_POINT}/private/root-ca.key"
    log_info "IMPORTANT: Close the store immediately after use: sudo $0 close"
}

# ---------------------------------------------------------------------------
# close: unmount and lock
# ---------------------------------------------------------------------------
cmd_close() {
    require_root
    require_cryptsetup

    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        log_info "Unmounting ${MOUNT_POINT}..."
        umount "${MOUNT_POINT}"
    fi

    if cryptsetup status "${MAPPER_NAME}" &>/dev/null; then
        log_info "Closing LUKS container..."
        cryptsetup close "${MAPPER_NAME}"
        log_info "Store locked. Root CA key is encrypted at rest."
    else
        log_info "Store is already closed."
    fi
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
cmd_status() {
    if cryptsetup status "${MAPPER_NAME}" &>/dev/null 2>&1; then
        log_warn "Store is OPEN — Root CA key is accessible at ${MOUNT_POINT}/private/"
        log_warn "Close it when done: sudo $0 close"
    else
        log_info "Store is CLOSED — Root CA key is encrypted."
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
    create) cmd_create ;;
    open)   cmd_open ;;
    close)  cmd_close ;;
    status) cmd_status ;;
    *)      usage ;;
esac
