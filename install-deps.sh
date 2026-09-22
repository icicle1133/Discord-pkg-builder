#!/usr/bin/env bash
set -euo pipefail

if command -v pacman &>/dev/null; then
  sudo pacman -Sy --needed --noconfirm curl tar fakeroot binutils
elif command -v dnf &>/dev/null; then
  sudo dnf install -y curl tar rpm-build
elif command -v yum &>/dev/null; then
  sudo yum install -y curl tar rpm-build
elif command -v zypper &>/dev/null; then
  sudo zypper --non-interactive install curl tar rpm-build
else
  echo "error: no supported package manager found" >&2
  exit 1
fi
