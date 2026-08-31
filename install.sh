#!/usr/bin/env bash
# Tiny Code native installer (macOS / Linux)
# Usage: curl -fsSL https://raw.githubusercontent.com/sadaigm/tiny-code/main/install.sh | bash
set -euo pipefail

REPO="sadaigm/tiny-code"
BASE_URL="https://github.com/${REPO}/releases/latest/download"

OS="$(uname -s)"
ARCH="$(uname -m)"

fail() { echo "install failed: $*" >&2; exit 1; }

download() { # <asset> <dest>
  local url="${BASE_URL}/$1"
  echo "Downloading ${url}"
  curl -fSL --progress-bar -o "$2" "$url" || fail "could not download $1"
}

case "${OS}" in
  Darwin)
    case "${ARCH}" in
      arm64)  ASSET="TinyCode-macos-arm64.dmg" ;;
      x86_64) ASSET="TinyCode-macos-x64.dmg" ;;
      *) fail "unsupported macOS architecture: ${ARCH}" ;;
    esac
    TMP_DMG="$(mktemp -d)/TinyCode.dmg"
    download "${ASSET}" "${TMP_DMG}"
    MOUNT="$(hdiutil attach -nobrowse -readonly -plist "${TMP_DMG}" \
      | grep -A1 '<key>mount-point</key>' | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')"
    [ -d "${MOUNT}" ] || fail "could not mount ${ASSET}"
    APP="$(find "${MOUNT}" -maxdepth 1 -name '*.app' | head -n1)"
    [ -n "${APP}" ] || fail "no .app found in ${ASSET}"
    rm -rf "/Applications/${APP##*/}"
    echo "Installing ${APP##*/} to /Applications"
    cp -R "${APP}" /Applications/ || fail "need write access to /Applications (try sudo)"
    hdiutil detach -quiet "${MOUNT}" || true
    echo "Installed. Note: unsigned build — on first launch right-click the app and choose Open."
    ;;

  Linux)
    [ "${ARCH}" = "x86_64" ] || fail "unsupported Linux architecture: ${ARCH} (builds available: x86_64)"
    BIN_DIR="${HOME}/.local/bin"
    mkdir -p "${BIN_DIR}"
    download "TinyCode-linux-x64.AppImage" "${BIN_DIR}/TinyCode.AppImage"
    chmod +x "${BIN_DIR}/TinyCode.AppImage"
    case ":${PATH}:" in
      *":${BIN_DIR}:"*) ;;
      *) echo "NOTE: add ${BIN_DIR} to your PATH to run 'TinyCode.AppImage' from a terminal." ;;
    esac
    echo "Installed: ${BIN_DIR}/TinyCode.AppImage"
    ;;

  *) fail "unsupported OS: ${OS}" ;;
esac
