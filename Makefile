# ==============================================================================
# OverlayTweak - Makefile (Extended for CPM Image-to-Vinyl Automation)
# ==============================================================================
# Builds Overlay.dylib for device (iphoneos).
# Requires macOS + Xcode. arm64 is required; arm64e is best-effort.
# Supports CPM vinyl automation: shape decomposition, touch injection,
# UI calibration, and execution control.
# ==============================================================================

TARGET_NAME = Overlay.dylib
MIN_IOS     = 14.0

SDK := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
ifeq ($(strip $(SDK)),)
SDK := $(SDKROOT)
endif
CC   = xcrun -sdk iphoneos clang

# Core OverlayTweak sources
CORE_SOURCES = \
    OverlayEntry.m \
    OverlayManager.m \
    OverlayView.m \
    SettingsViewController.m

# CPM Automation sources (all .m files in Core and UI directories)
CPM_CORE_SOURCES = \
    Core/CPMVinylShape.m \
    Core/CPMShapeDecomposer.m \
    Core/CPMTouchInjector.m \
    Core/CPMExecutionController.m \
    Core/CPMUICalibration.m

CPM_UI_SOURCES = \
    UI/CPMAutoDrawViewController.m \
    UI/CPMROIOverlayView.m

SOURCES = $(CORE_SOURCES) $(CPM_CORE_SOURCES) $(CPM_UI_SOURCES)

CFLAGS = -isysroot "$(SDK)" \
        -miphoneos-version-min=$(MIN_IOS) \
        -fobjc-arc \
        -fvisibility=hidden \
        -O2 \
        -g0 \
        -I. \
        -I Core \
        -I UI \
        -Wno-deprecated-declarations \
        -Wno-unused-variable \
        -Wno-objc-missing-super-calls \
        -Wno-partial-availability

# Link frameworks
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
          -framework CoreImage \
          -framework Accelerate \
          -framework IOKit \
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
	@echo ""
	@echo "CPM Automation enabled: $(CPM_CORE_SOURCES) $(CPM_UI_SOURCES)"

check-sdk:
	@if [ -z "$(SDK)" ]; then \
		echo "ERROR: iOS SDK not found."; \
		echo "Install Xcode and run: xcode-select --install"; \
		echo "Then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
		exit 1; \
	fi
	@echo "[SDK] $(SDK)"

check:
	@python3 scripts/check_objc.py 2>/dev/null || true

clean:
	@rm -f $(SOURCES:.m=.o) $(TARGET_NAME) $(TARGET_NAME).arm64 $(TARGET_NAME).arm64e
	@echo "[CLEAN] done"

# Inject into an IPA (requires insert_dylib)
inject:
	@if [ ! -f "$(TARGET_NAME)" ]; then \
		echo "ERROR: $(TARGET_NAME) not built. Run 'make' first."; \
		exit 1; \
	fi
	@if [ -z "$(IPA_PATH)" ]; then \
		echo "Usage: make inject IPA_PATH=/path/to/game.ipa"; \
		exit 1; \
	fi
	@echo "[Inject] $(IPA_PATH) with $(TARGET_NAME)"
	@mkdir -p tools
	@if [ ! -f tools/insert_dylib ]; then \
		echo "[Clone] insert_dylib"; \
		git clone https://github.com/tyilo/insert_dylib.git /tmp/insert_dylib 2>/dev/null || true; \
		cc /tmp/insert_dylib/insert_dylib/main.c -o tools/insert_dylib; \
	fi
	@./scripts/inject.sh $(IPA_PATH) $(TARGET_NAME)
	@echo "[Done] $(IPA_PATH:.ipa=_injected.ipa)"

# Run tests (if available)
test:
	@echo "[Test] No automated tests configured"
	@echo "Manual testing required on device"

# Show CPM module info
cpm-info:
	@echo "CPM Image-to-Vinyl Automation Module"
	@echo "======================================"
	@echo "Max layers: 200 (configurable up to 300)"
	@echo "Touch delay: 15ms (configurable 5-100ms)"
	@echo "Color quantization: K-Means (8 clusters)"
	@echo "Shape types: Square, Circle, Triangle, Line, Polygon"
	@echo "UI calibration: cpm_ui_anchors.json"

# Build and display info
info:
	@echo "OverlayTweak v$(shell grep 'kOLVersion' OverlayCommon.h | head -1 | sed 's/.*@\"\\(.*\\)\".*/\\1/')"
	@echo "Sources: $(words $(SOURCES)) files"
	@echo "Core: $(words $(CORE_SOURCES)) files"
	@echo "CPM Core: $(words $(CPM_CORE_SOURCES)) files"
	@echo "CPM UI: $(words $(CPM_UI_SOURCES)) files"
