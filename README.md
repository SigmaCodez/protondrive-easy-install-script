# rclone Proton Drive mount on login (Ubuntu / systemd --user)

This repository provides a simple installer that:

- Installs **rclone** (official installer) and **FUSE3**
- Creates an **rclone Proton Drive** remote
- Creates a **systemd user service** to mount Proton Drive automatically on login
- Keeps the mount running in the background and restarts on failure

> Note: rclone's Proton Drive backend is documented by rclone. You should have logged into Proton Drive at least once via a normal Proton client/browser so your account keys exist.

## Tested on
- Ubuntu (works on modern Ubuntu releases with systemd user services)

## Quick start

```bash
chmod +x install.sh
./install.sh
```

After installation:

```bash
systemctl --user status rclone-protondrive
journalctl --user -u rclone-protondrive -f
ls -la ~/ProtonDrive
```

## What it installs/configures

- Mount point: `~/ProtonDrive`
- Remote name: `ProtonDrive` (change in `install.sh` if you want)
- systemd user unit: `~/.config/systemd/user/rclone-protondrive.service`

## Uninstall / disable

```bash
systemctl --user disable --now rclone-protondrive
rm -f ~/.config/systemd/user/rclone-protondrive.service
systemctl --user daemon-reload

# optionally delete the remote
rclone config delete ProtonDrive
```

## Security notes

- The script uses `rclone obscure` to store the password in rclone config. This is **obfuscation**, not encryption.
- If you prefer not to store credentials, configure the remote manually (`rclone config`) and skip the remote-creation part of the script.

## License
MIT
