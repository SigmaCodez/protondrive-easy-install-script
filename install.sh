\
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# install.sh — Proton Drive "sync-on-change" setup (Option B)
#
# Clean install on Ubuntu:
# 1) Install dependencies (curl, unzip, fuse3, inotify-tools)
# 2) Install rclone (official installer)
# 3) Create rclone Proton Drive remote (type=protondrive)
# 4) Create a local working folder (LOCAL_DIR)
# 5) Create a systemd --user service that watches LOCAL_DIR and runs
#    rclone sync to Proton Drive after changes (debounced)
#
# Notes:
# - This is NOT a realtime sync engine; it triggers rclone sync after changes.
# - It is "local-first": you work in LOCAL_DIR; uploads happen via rclone sync.
# - Proton Drive backend may be unstable; this script uses a mitigation flag:
#   --protondrive-replace-existing-draft=true
# ------------------------------------------------------------

# -----------------------------
# Defaults (press Enter to accept)
# -----------------------------
DEFAULT_REMOTE_NAME="ProtonDrive"
DEFAULT_LOCAL_DIR="${HOME}/ProtonDriveLocal"
DEFAULT_REMOTE_PATH="ProtonDrive:/Backup"
DEFAULT_DEBOUNCE_SECONDS="10"
DEFAULT_TRANSFERS="1"
DEFAULT_CHECKERS="1"

echo "==> Proton Drive sync-on-change installer (Ubuntu / systemd --user)"
echo

# -----------------------------
# 1) Dependencies
# -----------------------------
echo "==> Installing dependencies (curl, unzip, fuse3, inotify-tools)..."
sudo apt-get update -y
sudo apt-get install -y curl unzip fuse3 inotify-tools

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
# 3) Configure remote + sync targets
# -----------------------------
read -rp "Remote name [${DEFAULT_REMOTE_NAME}]: " REMOTE_NAME
REMOTE_NAME="${REMOTE_NAME:-$DEFAULT_REMOTE_NAME}"

read -rp "Local working folder (edit here locally) [${DEFAULT_LOCAL_DIR}]: " LOCAL_DIR
LOCAL_DIR="${LOCAL_DIR:-$DEFAULT_LOCAL_DIR}"

read -rp "Remote destination path [${DEFAULT_REMOTE_PATH}]: " REMOTE_PATH
REMOTE_PATH="${REMOTE_PATH:-$DEFAULT_REMOTE_PATH}"

read -rp "Debounce seconds (wait after changes before syncing) [${DEFAULT_DEBOUNCE_SECONDS}]: " DEBOUNCE_SECONDS
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-$DEFAULT_DEBOUNCE_SECONDS}"

read -rp "Transfers (parallel uploads) [${DEFAULT_TRANSFERS}]: " TRANSFERS
TRANSFERS="${TRANSFERS:-$DEFAULT_TRANSFERS}"

read -rp "Checkers (parallel checks) [${DEFAULT_CHECKERS}]: " CHECKERS
CHECKERS="${CHECKERS:-$DEFAULT_CHECKERS}"

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
"${RCLONE_BIN}" lsd "${REMOTE_NAME}:" || echo "WARN: Remote test failed. Sync may fail until auth/keys are OK."

# -----------------------------
# 4) Create local working folder
# -----------------------------
echo "==> Creating local working folder: ${LOCAL_DIR}"
mkdir -p "${LOCAL_DIR}"

# -----------------------------
# 5) Create watcher sync script
# -----------------------------
echo "==> Installing watcher script..."
mkdir -p "${HOME}/bin"
WATCH_SCRIPT="${HOME}/bin/protondrive-watch-sync.sh"

cat > "${WATCH_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Values are injected by the installer into an env file read by systemd.
ENV_FILE="${HOME}/.config/protondrive-sync.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

echo "==> Watching: ${LOCAL_DIR}"
echo "==> Syncing to: ${REMOTE_PATH}"
echo "==> Debounce: ${DEBOUNCE_SECONDS}s"
echo

# Main loop: wait for changes, then sync after a quiet period
while true; do
  # Wait for any change events; ignore noisy transient errors
  inotifywait -r -e modify,create,delete,move "${LOCAL_DIR}" >/dev/null 2>&1 || true

  # Debounce window
  sleep "${DEBOUNCE_SECONDS}"

  # Run sync (local -> remote)
  "${RCLONE_BIN}" sync "${LOCAL_DIR}" "${REMOTE_PATH}" \
    --protondrive-replace-existing-draft=true \
    --transfers "${TRANSFERS}" \
    --checkers "${CHECKERS}" \
    --log-level INFO || true
done
EOF

chmod +x "${WATCH_SCRIPT}"

# Write env file used by the watcher service
echo "==> Writing environment file..."
mkdir -p "${HOME}/.config"
ENV_FILE="${HOME}/.config/protondrive-sync.env"
cat > "${ENV_FILE}" <<EOF
# Generated by install.sh
RCLONE_BIN=${RCLONE_BIN}
LOCAL_DIR=${LOCAL_DIR}
REMOTE_PATH=${REMOTE_PATH}
DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS}
TRANSFERS=${TRANSFERS}
CHECKERS=${CHECKERS}
EOF

# -----------------------------
# 6) Create systemd user service for watch-sync
# -----------------------------
echo "==> Creating systemd --user service..."
mkdir -p "${HOME}/.config/systemd/user"
UNIT_FILE="${HOME}/.config/systemd/user/protondrive-watch-sync.service"

cat > "${UNIT_FILE}" <<EOF
[Unit]
Description=Proton Drive sync on change (rclone + inotify)
After=network-online.target

[Service]
Type=simple
ExecStart=%h/bin/protondrive-watch-sync.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

echo "==> Enabling and starting the watcher service..."
systemctl --user daemon-reload
systemctl --user enable protondrive-watch-sync.service
systemctl --user restart protondrive-watch-sync.service

echo
echo "==> Done!"
echo
echo "Local working folder:"
echo "  ${LOCAL_DIR}"
echo
echo "Service status:"
echo "  systemctl --user status protondrive-watch-sync"
echo
echo "Follow logs:"
echo "  journalctl --user -u protondrive-watch-sync -f"
echo
echo "Tip: Work ONLY in the local folder above. Uploads happen via rclone sync after changes."
