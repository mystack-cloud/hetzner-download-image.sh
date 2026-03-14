#!/bin/sh
# get.hetzner-download-image.sh - Install hetzner-download-image.sh (download container image as rootfs for Hetzner installimage)
# Usage: curl https://get.hetzner-download-image.sh | sh -s
#    or: wget -qO- https://get.hetzner-download-image.sh | sh -s
#
# Installs to $HOME/.local/bin by default. Override: INSTALL_DIR=/path SCRIPT_URL=url
# Adds install dir to PATH in ~/.bashrc, ~/.zshrc, or ~/.profile. Set SKIP_PATH=1 to skip.
# Dependencies: curl|wget (for install), then jq, tar; gzip optional. Set INSTALL_DEPS=1 to try installing missing deps.

set -e

INSTALL_DEPS="${INSTALL_DEPS:-1}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/mystack-cloud/hetzner-download-image.sh/main/hetzner-download-image.sh}"

# Required: curl, jq, tar. gzip optional (for .tar.gz).
check_dep() { command -v "$1" >/dev/null 2>&1; }
missing_deps() {
  _m=""
  check_dep curl || _m="${_m} curl"
  check_dep jq   || _m="${_m} jq"
  check_dep tar  || _m="${_m} tar"
  echo "$_m"
}

try_install_deps() {
  _missing=$(missing_deps)
  [ -z "$_missing" ] && return 0
  if check_dep apt-get 2>/dev/null; then
    echo "Installing dependencies (sudo apt-get)..."
    sudo apt-get update -qq && sudo apt-get install -y curl jq tar gzip
  elif check_dep dnf 2>/dev/null; then
    echo "Installing dependencies (sudo dnf)..."
    sudo dnf install -y curl jq tar gzip
  elif check_dep yum 2>/dev/null; then
    echo "Installing dependencies (sudo yum)..."
    sudo yum install -y curl jq tar gzip
  elif check_dep apk 2>/dev/null; then
    echo "Installing dependencies (sudo apk)..."
    sudo apk add --no-cache curl jq tar gzip
  elif check_dep brew 2>/dev/null; then
    echo "Installing dependencies (brew)..."
    brew install curl jq gzip
  else
    echo "Could not detect package manager to install:$_missing" >&2
    return 1
  fi
}

echo "hetzner-download-image.sh installer"
echo ""

if [ "$INSTALL_DEPS" = "1" ]; then
  try_install_deps || true
fi

_missing=$(missing_deps)
if [ -n "$_missing" ]; then
  echo "Missing required commands:$_missing" >&2
  echo "Install them, or run with INSTALL_DEPS=1 to try automatic install (apt/dnf/yum/apk/brew)." >&2
  echo "Example (Debian/Ubuntu): sudo apt-get install curl jq tar gzip" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
if ! [ -d "$INSTALL_DIR" ]; then
  echo "Error: could not create directory: $INSTALL_DIR" >&2
  exit 1
fi

echo "Downloading hetzner-download-image.sh..."
if command -v curl >/dev/null 2>&1; then
  curl -sSLf "$SCRIPT_URL" -o "${INSTALL_DIR}/hetzner-download-image.sh"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "${INSTALL_DIR}/hetzner-download-image.sh" "$SCRIPT_URL"
else
  echo "Error: need curl or wget to download" >&2
  exit 1
fi

chmod +x "${INSTALL_DIR}/hetzner-download-image.sh"
echo "Installed to: ${INSTALL_DIR}/hetzner-download-image.sh"

# Auto-add install dir to PATH in shell rc if not already there (set SKIP_PATH=1 to skip)
add_to_path() {
  _dir="$1"
  [ "$SKIP_PATH" = "1" ] && return 0
  _path_line="export PATH=\"${_dir}:\$PATH\""
  for _rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
    [ ! -f "$_rc" ] && continue
    if grep -q "# hetzner-download-image.sh" "$_rc" 2>/dev/null; then
      return 0
    fi
    echo "" >> "$_rc"
    echo "# hetzner-download-image.sh" >> "$_rc"
    echo "$_path_line" >> "$_rc"
    echo "Added to PATH in $_rc"
    return 0
  done
  return 0
}

if [ -x "${INSTALL_DIR}/hetzner-download-image.sh" ]; then
  add_to_path "$INSTALL_DIR"
  echo ""
  echo "Run: hetzner-download-image.sh ghcr.io/myorg/debian-13:latest"
  echo "  (or in this shell: export PATH=\"${INSTALL_DIR}:\$PATH\")"
fi
