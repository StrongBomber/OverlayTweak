#!/bin/bash
# OverlayTweak — local macOS build wrapper
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

echo ""
echo "=========================================="
echo "  OverlayTweak — macOS Build"
echo "=========================================="
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
    error "This script requires macOS + Xcode."
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    error "Xcode Command Line Tools not found.\nInstall: xcode-select --install"
fi

step "Xcode"
xcodebuild -version | head -2

step "iOS SDK"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
if [ -z "${SDK_PATH}" ]; then
    error "iPhoneOS SDK not found. Open Xcode once and install the iOS platform."
fi
info "SDK: ${SDK_PATH}"

cd "$(dirname "$0")"
step "Clean"
make clean >/dev/null 2>&1 || true

step "Build"
make

if [ ! -f Overlay.dylib ]; then
    error "Overlay.dylib was not produced."
fi

echo ""
echo "=========================================="
echo "  Success"
echo "=========================================="
info "File: Overlay.dylib"
info "Size: $(ls -lh Overlay.dylib | awk '{print $5}')"
info "Arch: $(lipo -info Overlay.dylib 2>/dev/null || echo unknown)"
echo ""
echo "Inject into an IPA:"
echo "  ./scripts/inject.sh ./Game.ipa ./Overlay.dylib"
echo ""
echo "Install the resulting *_injected.ipa with TrollStore."
echo ""
