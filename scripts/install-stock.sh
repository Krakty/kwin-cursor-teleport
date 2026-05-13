#!/usr/bin/env bash
# Restore stock kwin from official Arch repos, overwriting the patched
# package. Use this when a patched session fails to start; run via SSH.
set -euo pipefail
echo "Restoring stock kwin from official Arch repos..."
sudo pacman -Syu --noconfirm kwin --overwrite '*'
echo
echo "Stock kwin restored. Log out and back in (or reboot) to use it."
