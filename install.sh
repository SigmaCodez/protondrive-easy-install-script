#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# install.sh
# Clean install on Ubuntu: rclone + Proton Drive remote + systemd --user mount
#
# What this does:
# 1) Installs dependencies (curl, fuse3, unzip)
# 2) Installs rclone (official installer)
# 3) Creates an rclone Proton Drive remote (type=protondrive)
# 4) Creates a systemd user service that mounts Proton Drive on login
#
# Includes a mitigation for common Proton Drive upload failures:
#   --protondrive-replace-existing-draft=true
# ------------------------------------------------------------

# -----------------------------
# Configuration (edit if needed)
# -----------------------------
REMOTE_NAME="ProtonDrive"
MOUNT_DIR="${HOME}/ProtonDrive"
SERVICE_NAME="rclone-protondrive"

echo "==> Installing rclone + Proton Drive and enabling auto-mount on login (systemd --user)"
echo "    Remote : ${REMOTE_NAME}"
echo "    Mount  : ${MOUNT_DIR}"
echo "    Unit   : ${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
echo

# -----------------------------
# 1) Dependencies + FUSE3
# -----------------------------
echo "==> Installing dependencies (curl, fuse3, unzip)..."
sudo apt-get update -y
sudo apt-get install -y curl fuse3 unzip

# -----------------------------
# 2) Install rclone
# -----------------------------
if command -v rclone >/dev/null 2>&1; then
  echo "==> rclone is already installed: $(rclone version | head -n 1)"
else
  echo "==> Installing rclone (official install script)..."
  curl -fsSL https://rclone.org/install.sh | sudo bash
  echo "==> rclone installed: $(rclone version | head -n 1)"
fi

RCLONE_BIN="$(command -v rclone)"

# -----------------------------
# 3) Create Proton Drive remote
# -----------------------------
echo
echo "==> Creating rclone remote '${REMOTE_NAME}' (type=protondrive)"
echo "    Tip: If you use 2FA, enter a fresh code."
echo "    Tip: If you have a two-password Proton setup, you may need the mailbox password."
echo

read -rp "Proton username (email): " PD_USER
read -rsp "Proton login password: " PD_PASS; echo
read -rp "2FA code (leave empty if not used): " PD_2FA
read -rsp "Mailbox password (only for two-password accounts; otherwise leave empty): " PD_MAILBOX; echo

echo "==> Obscuring secrets for rclone config (obfuscation, not encryption)..."
PD_PASS_OBSCURED="$("${RCLONE_BIN}" obscure "$PD_PASS")"
PD_MAILBOX_OBSCURED=""
if [[ -n "${PD_MAILBOX}" ]]; then
  PD_MAILBOX_OBSCURED="$("${RCLONE_BIN}" obscure "$PD_MAILBOX")"
fi

echo "==> Removing existing remote with the same name (if any)..."
"${RCLONE_BIN}" config delete "${REMOTE_NAME}" >/dev/null 2>&1 || true

echo "==> Creating remote via 'rclone config create'..."
ARGS=(config create "${REMOTE_NAME}" protondrive username "${PD_USER}" password "${PD_PASS_OBSCURED}")
if [[ -n "${PD_2FA}" ]]; then
  ARGS+=(2fa "${PD_2FA}")
fi
if [[ -n "${PD_MAILBOX_OBSCURED}" ]]; then
  ARGS+=(mailbox_password "${PD_MAILBOX_OBSCURED}")
fi
"${RCLONE_BIN}" "${ARGS[@]}"

echo "==> Testing remote connectivity (rclone lsd ${REMOTE_NAME}: )..."
"${RCLONE_BIN}" lsd "${REMOTE_NAME}:" || echo "WARN: Remote test failed. You can still continue, but uploads may fail until auth/keys are OK."

# -----------------------------
# 4) Create mount directory
# -----------------------------
echo "==> Creating mount directory: ${MOUNT_DIR}"
mkdir -p "${MOUNT_DIR}"

# -----------------------------
# 5) Create systemd user unit (auto-start on login)
# -----------------------------
echo "==> Creating systemd user service..."
mkdir -p "${HOME}/.config/systemd/user"

UNIT_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=Rclone mount Proton Drive (${REMOTE_NAME})
After=network-online.target

[Service]
Type=simple
ExecStart=${RCLONE_BIN} mount ${REMOTE_NAME}:/ %h/ProtonDrive --vfs-cache-mode full --protondrive-replace-existing-draft=true
ExecStop=/bin/fusermount3 -u %h/ProtonDrive
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

echo "==> Enabling and starting the service..."
systemctl --user daemon-reload
systemctl --user enable "${SERVICE_NAME}.service"
systemctl --user restart "${SERVICE_NAME}.service"

echo
echo "==> Done!"
echo
echo "Check status:"
echo "  systemctl --user status ${SERVICE_NAME}"
echo
echo "Follow logs:"
echo "  journalctl --user -u ${SERVICE_NAME} -f"
echo
echo "Test mount:"
echo "  ls -la ${MOUNT_DIR}"
echo
echo "If you still see upload loops (422 / draft exists), try deleting the affected file in Proton Drive web and empty trash, then re-upload."
