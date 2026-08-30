# ==============================================================================
# OverlayTweak - Makefile
# ==============================================================================
# Builds Overlay.dylib for device (iphoneos).
# Requires macOS + Xcode. arm64 is required; arm64e is best-effort.
# ==============================================================================

TARGET_NAME = Overlay.dylib
MIN_IOS     = 14.0

SDK := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
ifeq ($(strip $(SDK)),)
SDK := $(SDKROOT)
endif
CC   = xcrun -sdk iphoneos clang

SOURCES = OverlayEntry.m OverlayManager.m OverlayView.m SettingsViewController.m

CFLAGS = -isysroot "$(SDK)" \
         -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc \
         -fvisibility=hidden \
         -O2 \
         -g0 \
         -I. \
         -Wno-deprecated-declarations \
         -Wno-unused-variable \
         -Wno-objc-missing-super-calls

LDFLAGS = -isysroot "$(SDK)" \
          -miphoneos-version-min=$(MIN_IOS) \
          -dynamiclib \
          -lobjc \
          -framework UIKit \
          -framework Foundation \
          -framework Photos \
          -framework PhotosUI \
          -framework CoreGraphics \
          -framework QuartzCore \
          -install_name @executable_path/$(TARGET_NAME)

.PHONY: all clean check-sdk check

all: check-sdk
	@echo "[CC/LD] arm64"
	$(CC) $(CFLAGS) $(LDFLAGS) -arch arm64 -o $(TARGET_NAME).arm64 $(SOURCES)
	@echo "[CC/LD] arm64e (optional)"
	@if $(CC) $(CFLAGS) $(LDFLAGS) -arch arm64e -o $(TARGET_NAME).arm64e $(SOURCES); then \
		echo "[LIPO] arm64 + arm64e"; \
		lipo -create -output $(TARGET_NAME) $(TARGET_NAME).arm64 $(TARGET_NAME).arm64e; \
	else \
		echo "[WARN] arm64e failed — shipping arm64 only"; \
		cp $(TARGET_NAME).arm64 $(TARGET_NAME); \
	fi
	@rm -f $(TARGET_NAME).arm64 $(TARGET_NAME).arm64e
	@echo "[STRIP] $(TARGET_NAME)"
	@xcrun -sdk iphoneos strip -x $(TARGET_NAME) 2>/dev/null || true
	@echo ""
	@echo "=========================================="
	@echo "  Built: $(TARGET_NAME)"
	@lipo -info $(TARGET_NAME) || true
	@ls -lh $(TARGET_NAME)
	@echo "=========================================="

check-sdk:
	@if [ -z "$(SDK)" ]; then \
		echo "ERROR: iOS SDK not found."; \
		echo "Install Xcode and run: xcode-select --install"; \
		echo "Then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
		exit 1; \
	fi
	@echo "[SDK] $(SDK)"

check:
	@python3 scripts/check_objc.py

clean:
	@rm -f $(SOURCES:.m=.o) $(TARGET_NAME) $(TARGET_NAME).arm64 $(TARGET_NAME).arm64e
	@echo "[CLEAN] done"
