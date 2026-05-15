# Rainy Day — rain-on-glass screensaver delivered as a regular .app.
#
# A background (LSUIElement) app that polls system idle time and shows
# a fullscreen WKWebView running raindrop-fx (MIT, SardineFish) when
# the user has been idle past a threshold. Dismisses on any mouse/key
# event.
#
# Built as `Rainy Day.app`, not as a `.saver` — see the helper-process
# and metal-port branches for prior screensaver-bundle attempts.

# ─── Project identity ────────────────────────────────────────────────────────
BUNDLE_NAME      := RainyDay
BUNDLE_TYPE      := app
PRODUCT_NAME     := Rainy Day.app
BUNDLE_ID        := cc.jorviksoftware.RainyDay
BUILD_SYSTEM     := swiftc

# Ship both a .zip (unzip + drag to /Applications) and a .pkg
# (signed/notarised installer that drops the .app into /Applications
# and avoids App Translocation). release.mk uses BUNDLE_TYPE to derive
# INSTALL_ROOT — `app` selects /Applications. PACKAGE_TYPE=zip is the
# primary artefact; ALSO_SHIP_PKG=true triggers a second pass for the
# .pkg. Same dual-ship pattern as the other public Jorvik apps.
PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true

SWIFT_FRAMEWORKS := Cocoa WebKit CoreGraphics ServiceManagement
SWIFT_SOURCES    := App/main.swift App/AppDelegate.swift App/ScreensaverWindow.swift \
                    App/WallpaperWindow.swift \
                    App/StatusItem.swift App/SettingsWindow.swift \
                    App/HotkeyRecorder.swift App/HotkeyManager.swift \
                    App/LockScreen.swift App/Screenshot.swift \
                    App/BackgroundsStore.swift \
                    App/SparkleDelegate.swift App/Log.swift \
                    App/JorvikKit/JorvikAboutView.swift App/JorvikKit/JorvikWindowHelper.swift \
                    App/JorvikKit/JorvikSettingsView.swift

EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS        := RainyDay.entitlements

# Stable signing identity for dev. Same identity production uses; ad-hoc
# (`-`) breaks TCC grants and the hardened runtime requirement Sparkle
# imposes on its embedded XPC services.
DEV_SIGN_IDENTITY := Developer ID Application: Jonthan Hollin (EG86BCGUE7)

# Release.mk lives in a sibling repo (PerpetualBeta/jorvik-release).
# It owns the production pipeline (stamping, notarisation, appcast
# generation) and processes EMBEDDED_FRAMEWORKS for proper Sparkle
# embedding/signing during release builds.
include ../jorvik-release/release.mk

.DEFAULT_GOAL := dev-build

.PHONY: dev-build run icon

# ─── Dev iteration targets ───────────────────────────────────────────────────

dev-build:
	@echo "→ dev build (arm64, signed Developer ID, Sparkle embedded)"
	@rm -rf "$(PRODUCT_NAME)"
	@mkdir -p "$(PRODUCT_NAME)/Contents/MacOS" "$(PRODUCT_NAME)/Contents/Resources" "$(PRODUCT_NAME)/Contents/Frameworks"
	swiftc -O -target arm64-apple-macos14.0 -sdk $(SDK) \
		$(addprefix -framework ,$(SWIFT_FRAMEWORKS)) \
		-F . \
		-Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
		-module-name $(BUNDLE_NAME) \
		-o "$(PRODUCT_NAME)/Contents/MacOS/$(BUNDLE_NAME)" \
		$(SWIFT_SOURCES)
	cp Info.plist "$(PRODUCT_NAME)/Contents/Info.plist"
	@echo "→ Copying Resources/ contents..."
	@cp -R Resources/* "$(PRODUCT_NAME)/Contents/Resources/"
	@echo "→ Embedding Sparkle.framework..."
	@cp -R Sparkle.framework "$(PRODUCT_NAME)/Contents/Frameworks/"
	@echo "→ Signing framework leaves-first..."
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>&1 | tail -1
	@codesign --force --options runtime --timestamp --sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)/Contents/Frameworks/Sparkle.framework" 2>&1 | tail -1
	@echo "→ Signing app bundle (entitlements + hardened runtime)..."
	codesign --force --options runtime --timestamp \
		--entitlements "$(ENTITLEMENTS)" \
		--sign "$(DEV_SIGN_IDENTITY)" \
		"$(PRODUCT_NAME)"
	@echo "→ Done: $(PRODUCT_NAME) (signed: $(DEV_SIGN_IDENTITY))"

run: dev-build
	pkill -f "/$(PRODUCT_NAME)/" 2>/dev/null || true
	open "$(PRODUCT_NAME)"

icon:
	@echo "→ Generating icon..."
	swift generate_icon.swift
