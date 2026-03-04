#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Configuration (edit as needed)
# -----------------------------
REMOTE_NAME="ProtonDrive"
MOUNT_DIR="${HOME}/ProtonDrive"
SERVICE_NAME="rclone-protondrive"

echo "==> This script installs rclone, configures Proton Drive, and sets up an auto-mount on login (systemd --user)."
echo

# -----------------------------
# 1) Dependencies + FUSE
# -----------------------------
echo "==> Installing dependencies (curl, fuse3, unzip)..."
sudo apt-get update -y
sudo apt-get install -y curl fuse3 unzip

# -----------------------------
# 2) Install rclone (official installer)
# -----------------------------
if command -v rclone >/dev/null 2>&1; then
  echo "==> rclone is already installed: $(rclone version | head -n 1)"
else
  echo "==> Installing rclone (official install script)..."
  curl -fsSL https://rclone.org/install.sh | sudo bash
  echo "==> rclone installed: $(rclone version | head -n 1)"
fi

# -----------------------------
# 3) Create Proton Drive remote
# -----------------------------
echo
echo "==> Creating Proton Drive remote: ${REMOTE_NAME}"
echo "    If you use 2FA, enter a fresh code."
echo "    If you have a two-password Proton setup, you may need the mailbox password."
echo

read -rp "Proton username (email): " PD_USER
read -rsp "Proton login password: " PD_PASS; echo
read -rp "2FA code (leave empty if not used): " PD_2FA
read -rsp "Mailbox password (only for two-password accounts; otherwise leave empty): " PD_MAILBOX; echo

echo "==> Obscuring secrets for rclone config (obfuscation, not encryption)..."
PD_PASS_OBSCURED="$(rclone obscure "$PD_PASS")"
PD_MAILBOX_OBSCURED=""
if [[ -n "${PD_MAILBOX}" ]]; then
  PD_MAILBOX_OBSCURED="$(rclone obscure "$PD_MAILBOX")"
fi

echo "==> Removing existing remote with the same name (if any)..."
rclone config delete "${REMOTE_NAME}" >/dev/null 2>&1 || true

echo "==> Creating remote via 'rclone config create'..."
ARGS=(config create "${REMOTE_NAME}" protondrive username "${PD_USER}" password "${PD_PASS_OBSCURED}")
if [[ -n "${PD_2FA}" ]]; then
  ARGS+=(2fa "${PD_2FA}")
fi
if [[ -n "${PD_MAILBOX_OBSCURED}" ]]; then
  ARGS+=(mailbox_password "${PD_MAILBOX_OBSCURED}")
fi
rclone "${ARGS[@]}"

echo "==> Testing remote connectivity (rclone lsd ${REMOTE_NAME}: )..."
rclone lsd "${REMOTE_NAME}:" || echo "WARN: Remote test failed. See README for common causes."

# -----------------------------
# 4) Create mount directory
# -----------------------------
echo "==> Creating mount directory: ${MOUNT_DIR}"
mkdir -p "${MOUNT_DIR}"

# -----------------------------
# 5) systemd user service (auto-start on login)
# -----------------------------
echo "==> Creating systemd user service..."
mkdir -p "${HOME}/.config/systemd/user"

SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Rclone mount Proton Drive (${REMOTE_NAME})
After=network-online.target

[Service]
Type=simple
ExecStart=$(command -v rclone) mount ${REMOTE_NAME}:/ %h/ProtonDrive --vfs-cache-mode full
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
echo "Check status:"
echo "  systemctl --user status ${SERVICE_NAME}"
echo "Follow logs:"
echo "  journalctl --user -u ${SERVICE_NAME} -f"
echo "Test mount:"
echo "  ls -la ${MOUNT_DIR}"
