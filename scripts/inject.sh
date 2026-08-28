#!/bin/bash
set -e
R='\033[0;31m'; G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
info() { echo -e "${G}[✓]${N} $1"; }
step() { echo -e "${B}[→]${N} $1"; }
err()  { echo -e "${R}[✗]${N} $1"; exit 1; }

[ $# -lt 2 ] && err "Kullanım: $0 <ipa> <dylib>"
IPA="$1"; DYLIB="$2"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSERT="$DIR/tools/insert_dylib"

[ ! -f "$IPA" ]   && err "IPA bulunamadı: $IPA"
[ ! -f "$DYLIB" ] && err "Dylib bulunamadı: $DYLIB"
[ ! -f "$INSERT" ] && err "insert_dylib bulunamadı: $INSERT"

TMP=$(mktemp -d); WRK="$TMP/work"; OUT="${IPA%.ipa}_injected.ipa"
trap "rm -rf $TMP" EXIT

step "1/5: IPA çıkarılıyor..."
mkdir -p "$WRK" && unzip -q "$IPA" -d "$WRK"
APP=$(find "$WRK/Payload" -name "*.app" -type d -maxdepth 1 | head -1)
[ -z "$APP" ] && err "App bulunamadı"
info "App: $(basename "$APP" .app)"

step "2/5: Dylib kopyalanıyor..."
cp "$DYLIB" "$APP/Overlay.dylib"
info "Kopyalandı."

step "3/5: Binary enjekte ediliyor..."
BIN_NAME=$(plutil -extract CFBundleExecutable raw "$APP/Info.plist" 2>/dev/null || defaults read "$APP/Info.plist" CFBundleExecutable 2>/dev/null)
BIN="$APP/$BIN_NAME"
[ ! -f "$BIN" ] && err "Binary bulunamadı: $BIN"
"$INSERT" --inplace --all-yes "@executable_path/Overlay.dylib" "$BIN"
info "Enjekte edildi."

step "4/5: İmzalanıyor..."
if command -v ldid &>/dev/null; then
    ldid -S "$APP/Overlay.dylib" && ldid -S "$BIN"
    info "ldid ile imzalandı."
elif command -v codesign &>/dev/null; then
    codesign --force --sign - "$APP/Overlay.dylib" 2>/dev/null
    codesign --force --sign - "$BIN" 2>/dev/null
    info "codesign ile imzalandı."
else
    echo "Uyarı: İmzalama aracı yok."
fi

step "5/5: Paketleniyor..."
cd "$WRK" && zip -qr "$OUT" Payload/
info "OK: $OUT"
