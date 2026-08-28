#!/bin/bash

# ==============================================================================
# OverlayTweak - macOS Build Script
# ==============================================================================
# Bu script macOS'ta Overlay.dylib derler.
# Xcode Command Line Tools gerektirir.
#
# Kullanım:
#   chmod +x build_macos.sh
#   ./build_macos.sh
# ==============================================================================

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "${BLUE}[→]${NC} $1"; }

echo ""
echo "=========================================="
echo "  OverlayTweak - macOS Build"
echo "=========================================="
echo ""

# ==============================================================================
# Gereksinim Kontrolleri
# ==============================================================================

# macOS kontrolü
if [[ "$(uname)" != "Darwin" ]]; then
    error "Bu script sadece macOS'ta çalışır!"
fi

# Xcode Command Line Tools kontrolü
if ! command -v xcodebuild &>/dev/null; then
    error "Xcode Command Line Tools bulunamadı!
Kurulum: xcode-select --install"
fi

# Xcode sürümü
step "Xcode kontrol ediliyor..."
XCODE_VERSION=$(xcodebuild -version | head -1)
info "$XCODE_VERSION"

# iOS SDK kontrolü
step "iOS SDK kontrol ediliyor..."
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

if [ -z "$SDK_PATH" ]; then
    warn "iOS SDK bulunamadı, Xcode açılıyor..."
    open -a Xcode
    echo ""
    echo "Lütfen:"
    echo "1. Xcode'u açın"
    echo "2. Preferences → Locations → iOS SDK'yi indirin"
    echo "3. Bu scripti tekrar çalıştırın"
    exit 1
fi

info "iOS SDK: $SDK_PATH"

# ==============================================================================
# Derleme
# ==============================================================================

echo ""
step "Derleme başlıyor..."

# Temizle
step "Temizleniyor..."
make clean 2>/dev/null || true

# Derle
step "Derleniyor..."
if ! make; then
    error "Derleme başarısız! Hata mesajlarını kontrol edin."
fi

# Başarı kontrolü
if [ ! -f "Overlay.dylib" ]; then
    error "Overlay.dylib oluşmadı!"
fi

# ==============================================================================
# Sonuç
# ==============================================================================

echo ""
echo "=========================================="
echo "  Derleme Başarılı!"
echo "=========================================="
echo ""
info "Dosya: Overlay.dylib"
info "Boyut: $(ls -lh Overlay.dylib | awk '{print $5}')"
info "Mimari: $(lipo -info Overlay.dylib 2>/dev/null || echo 'arm64 + arm64e')"
echo ""
echo "=========================================="
echo "  Sonraki Adımlar"
echo "=========================================="
echo ""
echo "1. insert_dylib'i derleyin (bir kerelik):"
echo "   git clone https://github.com/49876540/insert_dylib.git"
echo "   cd insert_dylib && clang insert_dylib.c -o insert_dylib"
echo "   cp insert_dylib ./tools/"
echo ""
echo "2. IPA'ya enjekte edin:"
echo "   ./scripts/inject.sh ./CarParking.ipa ./Overlay.dylib"
echo ""
echo "3. TrollStore ile yükleyin:"
echo "   CarParking_injected.ipa → Install"
echo ""
