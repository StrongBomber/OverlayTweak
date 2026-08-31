#!/bin/bash
# Inject Overlay.dylib into an IPA (adds LC_LOAD_DYLIB via insert_dylib).
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; B='\033[0;34m'; N='\033[0m'
info() { echo -e "${G}[✓]${N} $1"; }
step() { echo -e "${B}[→]${N} $1"; }
err()  { echo -e "${R}[✗]${N} $1"; exit 1; }

usage() { err "Usage: $0 <app.ipa> <Overlay.dylib>"; }

[ $# -lt 2 ] && usage

IPA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
DYLIB="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
DIR="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$IPA" ]   || err "IPA not found: $IPA"
[ -f "$DYLIB" ] || err "Dylib not found: $DYLIB"

find_insert() {
    local c
    for c in \
        "$DIR/tools/insert_dylib" \
        "$(command -v insert_dylib 2>/dev/null || true)" \
        "$HOME/bin/insert_dylib"
    do
        [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

INSERT="$(find_insert || true)"
if [ -z "$INSERT" ]; then
    err "insert_dylib not found.
Build it once:
  git clone https://github.com/tyilo/insert_dylib.git /tmp/insert_dylib
  cc /tmp/insert_dylib/insert_dylib/main.c -o $DIR/tools/insert_dylib
Then re-run this script."
fi

TMP="$(mktemp -d)"
WRK="$TMP/work"
OUT="${IPA%.ipa}_injected.ipa"
trap 'rm -rf "$TMP"' EXIT

step "1/5 Extract IPA"
mkdir -p "$WRK"
unzip -q "$IPA" -d "$WRK"
APP="$(find "$WRK/Payload" -name "*.app" -type d -maxdepth 1 | head -1)"
[ -n "$APP" ] || err "No .app inside Payload/"
info "App: $(basename "$APP" .app)"

step "2/5 Copy dylib"
cp "$DYLIB" "$APP/Overlay.dylib"
info "Copied Overlay.dylib"

step "3/5 Inject load command"
BIN_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw "$APP/Info.plist" 2>/dev/null \
    || defaults read "$APP/Info.plist" CFBundleExecutable 2>/dev/null || true)"
[ -n "$BIN_NAME" ] || err "Could not read CFBundleExecutable"
BIN="$APP/$BIN_NAME"
[ -f "$BIN" ] || err "Binary not found: $BIN"

if otool -L "$BIN" 2>/dev/null | grep -q Overlay.dylib; then
    info "Already injected — skipping insert_dylib"
else
    "$INSERT" --inplace --all-yes "@executable_path/Overlay.dylib" "$BIN"
    info "Injected @executable_path/Overlay.dylib"
fi

step "4/5 Ad-hoc sign"
if command -v ldid >/dev/null 2>&1; then
    ldid -S "$APP/Overlay.dylib"
    ldid -S "$BIN"
    info "Signed with ldid"
elif command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$APP/Overlay.dylib" 2>/dev/null || true
    codesign --force --sign - --timestamp=none "$BIN" 2>/dev/null || true
    info "Ad-hoc signed with codesign"
else
    echo "Warning: no ldid/codesign — TrollStore may still install it."
fi

step "5/5 Repack"
# zip must be created from inside the work dir so Payload/ is at the root.
ABS_OUT="$OUT"
(
    cd "$WRK"
    rm -f "$ABS_OUT"
    zip -qr "$ABS_OUT" Payload
)
info "OK: $OUT"
