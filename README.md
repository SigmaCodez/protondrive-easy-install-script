# Proton Drive: Read-only mount + local staging + auto-upload (rclone)

This project sets up a **hybrid workflow** for Proton Drive on Ubuntu/Linux:

- **Browse Proton Drive as a filesystem** via an **rclone read-only mount**
- **Edit/copy files locally** in a **staging folder**
- A watcher uploads changes **automatically** using `rclone move` (so the staging area is cleaned up after a successful upload)

This avoids the most common Proton Drive issues when uploading through `rclone mount` / VFS.

## How it works

Folders created by the installer (defaults):

- `~/ProtonDriveRO` — **read-only** mount of Proton Drive (browse/download)
- `~/ProtonDriveStage` — local **staging** folder (edit/copy here)

Uploads:
- Any file you place or modify in `~/ProtonDriveStage` will be uploaded to `ProtonDrive:/StageUpload`
- After a successful upload, files are removed from the staging folder automatically

Helpers:
- `pd-edit <remote-relative-path>` downloads a remote file into the staging folder and opens it.
  When you save/close it, the watcher will upload it back to the remote upload path.

## Install (Ubuntu)

```bash
chmod +x install.sh
./install.sh
```

## Services

- `rclone-protondrive-ro-mount` (read-only mount)
- `protondrive-stage-uploader` (watcher/uploader)

Status / logs:

```bash
systemctl --user status rclone-protondrive-ro-mount protondrive-stage-uploader
journalctl --user -u rclone-protondrive-ro-mount -f
journalctl --user -u protondrive-stage-uploader -f
```

## Notes / limitations

- This is not a true 2-way sync engine. It is **staging → upload**.
- Upload stability depends on the Proton Drive backend in rclone.
- The installer enables mitigations:
  - uploads happen via `rclone move` (not via VFS writeback)
  - `--protondrive-replace-existing-draft=true`
  - low concurrency (`--transfers 1 --checkers 1`)
  - `flock` to prevent overlapping runs
  - only uploads files that have been unchanged for a short “settle time”

## License

MIT
