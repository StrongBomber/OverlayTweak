# ==============================================================================
# OverlayTweak - Makefile
# ==============================================================================
# iOS dylib derleme dosyası.
# macOS + Xcode Command Line Tools gerektirir.
# ==============================================================================

TARGET_NAME = Overlay.dylib

# Mimari: arm64 (iPhone 5s+) ve arm64e (iPhone XS+)
ARCHS = -arch arm64 -arch arm64e

# iOS SDK yolu (Xcode'dan otomatik bulunur)
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

# Derleyici
CC = xcrun -sdk iphoneos clang

# Minimum iOS sürümü
MIN_IOS = 14.0

# Derleme bayrakları
CFLAGS = $(ARCHS) \
         -isysroot $(SDK) \
         -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc \
         -fmodules \
         -fvisibility=hidden \
         -O2 \
         -Wno-deprecated-declarations \
         -Wno-unused-variable

# Linker bayrakları
LDFLAGS = $(ARCHS) \
          -isysroot $(SDK) \
          -miphoneos-version-min=$(MIN_IOS) \
          -dynamiclib \
          -lobjc \
          -framework UIKit \
          -framework Foundation \
          -framework Photos \
          -framework PhotosUI \
          -framework CoreGraphics \
          -framework QuartzCore \
          -install_name @rpath/$(TARGET_NAME)

# Kaynak dosyalar
SOURCES = OverlayEntry.m \
          OverlayManager.m \
          OverlayView.m \
          SettingsViewController.m

# Nesne dosyaları
OBJECTS = $(SOURCES:.m=.o)

# ==============================================================================
# Kurallar
# ==============================================================================

.PHONY: all clean check-sdk

# SDK kontrolü
check-sdk:
	@if [ -z "$(SDK)" ]; then \
		echo "HATA: iOS SDK bulunamadı!"; \
		echo "Xcode'u açın ve iOS SDK'yi indirin."; \
		exit 1; \
	fi

# Ana derleme kuralı
all: check-sdk $(OBJECTS)
	@echo ""
	@echo "[LINK] $(TARGET_NAME)"
	$(CC) $(LDFLAGS) -o $(TARGET_NAME) $(OBJECTS)
	@echo "[STRIP] $(TARGET_NAME)"
	xcrun -sdk iphoneos strip -x $(TARGET_NAME) 2>/dev/null || true
	@echo ""
	@echo "=========================================="
	@echo "  Derleme başarılı: $(TARGET_NAME)"
	@echo "=========================================="
	@echo ""
	@ls -lh $(TARGET_NAME)

# .m -> .o derleme kuralı
%.o: %.m
	@echo "[CC] $<"
	$(CC) $(CFLAGS) -c $< -o $@

# Temizleme
clean:
	@echo "[CLEAN] Temizleniyor..."
	@rm -f $(OBJECTS) $(TARGET_NAME)
	@echo "[CLEAN] Tamamlandı."
