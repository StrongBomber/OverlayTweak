# OverlayTweak

iOS dylib overlay for sideloaded / TrollStore apps. Inject `Overlay.dylib` into an IPA and you get a movable, scalable image overlay on top of the host app (games, etc.) without capturing the game’s touches when locked.

## Features

- Scene-attached overlay window (iOS 13+). Does **not** steal the host key window.
- Passthrough hit-testing: locked overlay and empty space go to the game.
- PHPicker image import (no `NSPhotoLibraryUsageDescription` required) + paste from clipboard.
- Overlay frame follows the photo (9:16 stays 9:16, 500×500 stays square). Custom W×H in settings, plus 1:1 / 9:16 / 16:9 / 4:3 / 3:4 presets.
- Opacity, scale, rotation (pinch / rotate / sliders), flip H/V, aspect fit/fill/stretch.
- Lock mode, hide/show overlay, hide menu (edge tab remains).
- Double-tap overlay to reset transform.
- Images saved as JPEG on disk (not bloated `NSUserDefaults` PNG) — less hitching.
- Debounced persistence, rasterized overlay layer.

Minimum iOS: **14.0**. Architectures: **arm64** (required) + **arm64e** (best-effort).

## Build

### GitHub Actions

Push or run **Actions → Build Overlay.dylib → Run workflow**. The artifact is `Overlay.dylib`.

### Local (macOS + Xcode)

```bash
chmod +x build_macos.sh
./build_macos.sh
```

or `make`.

## Inject into an IPA

You need [`insert_dylib`](https://github.com/tyilo/insert_dylib):

```bash
mkdir -p tools
git clone https://github.com/tyilo/insert_dylib.git /tmp/insert_dylib
cc /tmp/insert_dylib/insert_dylib/main.c -o tools/insert_dylib

./scripts/inject.sh ./Game.ipa ./Overlay.dylib
```

Install `Game_injected.ipa` with **TrollStore**.

Optional: limit to one app by compiling with

```bash
make CFLAGS='... -DOVERLAY_TARGET_BUNDLE_ID=@\"com.example.game\"'
```

(or set `kTargetBundleID` in `OverlayEntry.m`).

## Usage

1. Launch the injected app. A ⚙️ button appears (safe-area aware, draggable).
2. Pick an image from Photos or paste from the clipboard.
3. Drag / pinch / rotate. **Lock** to send touches through to the game.
4. Hide the ⚙️ button if it gets in the way — a small edge tab brings it back.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| GitHub Action fails at **Build** | 1.1.0 fixes the compile errors that broke `make` (`OLLog`, `addChildViewController` on `NSObject`, private properties). `arm64e` is optional in the Makefile. An upgraded workflow lives at `ci/build.yml` if you want to replace `.github/workflows/build.yml`. |
| Overlay never appears | Check Console for `[OverlayTweak]`. Confirm the dylib is listed in `otool -L` on the app binary. |
| Touches blocked | Enable **Lock**. |
| Photo picker blank / no touches | 1.1.0 presents PHPicker on the overlay window and temporarily makes it key. |
| Stutter while sliding opacity | Saves are debounced; images are JPEG on disk. Rebuild with 1.1.0. |
