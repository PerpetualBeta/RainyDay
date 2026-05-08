# Rainy Day — rain-on-glass screensaver.
#
# Embeds raindrop-fx (MIT, by SardineFish — vendored as
# Resources/raindrop-fx.bundle.js) inside a WKWebView. The Swift side is
# a thin host; all rendering lives in the JS bundle. See ATTRIBUTIONS.md.
#
# This Makefile drives both day-to-day dev iteration AND the release
# pipeline. The release pipeline is delegated to the shared `release.mk`
# include (in PerpetualBeta/jorvik-release); the dev targets below are
# Rainy Day-specific and intentionally fast — no stamping, signing, or
# notarisation.

# ─── Project identity ────────────────────────────────────────────────────────
BUNDLE_NAME      := RainyDay
BUNDLE_TYPE      := saver
PRODUCT_NAME     := RainyDay.saver
BUNDLE_ID        := cc.jorviksoftware.RainyDay
BUILD_SYSTEM     := swiftc

SWIFT_FRAMEWORKS := Cocoa ScreenSaver WebKit
SWIFT_SOURCES    := RainyDayView.swift

PACKAGE_TYPE     := pkg
ALSO_SHIP_PKG    := false

# Release.mk lives in a sibling repo (PerpetualBeta/jorvik-release).
include ../jorvik-release/release.mk

# Override release.mk's default goal: a bare `make` should build a fast
# local saver, not run a full release pipeline.
.DEFAULT_GOAL := dev-build

# ─── Dev iteration targets ───────────────────────────────────────────────────

.PHONY: dev-build dev-install testapp run icon

LOCAL_BUNDLE := RainyDay.saver
LOCAL_INSTALL_DIR := $(HOME)/Library/Screen Savers

# Test app — same RainyDayView the .saver bundle uses, hosted in an
# NSWindow harness in TestApp/. The test app is a regular .app so it
# can find resources via Bundle.main.
TESTAPP_SOURCES := TestApp/main.swift RainyDayView.swift

# Single-arch fast build for local install.
dev-build:
	@echo "→ dev build (arm64 only, ad-hoc)"
	@mkdir -p $(LOCAL_BUNDLE)/Contents/MacOS $(LOCAL_BUNDLE)/Contents/Resources
	swiftc -O -target arm64-apple-macos14.0 -sdk $(SDK) \
		-framework Cocoa -framework ScreenSaver -framework WebKit \
		-emit-library -module-name $(BUNDLE_NAME) \
		-o $(LOCAL_BUNDLE)/Contents/MacOS/$(BUNDLE_NAME) \
		$(SWIFT_SOURCES)
	cp Info.plist $(LOCAL_BUNDLE)/Contents/Info.plist
	@echo "→ Copying Resources/ contents to bundle..."
	@cp -R Resources/* $(LOCAL_BUNDLE)/Contents/Resources/
	codesign --force --sign - $(LOCAL_BUNDLE)
	@echo "→ Done: $(LOCAL_BUNDLE)"

dev-install: dev-build
	@echo "→ Installing to $(LOCAL_INSTALL_DIR)..."
	@mkdir -p "$(LOCAL_INSTALL_DIR)"
	rm -rf "$(LOCAL_INSTALL_DIR)/$(LOCAL_BUNDLE)"
	cp -R $(LOCAL_BUNDLE) "$(LOCAL_INSTALL_DIR)/$(LOCAL_BUNDLE)"
	-killall ScreenSaverEngine 2>/dev/null || true
	-killall legacyScreenSaver 2>/dev/null || true
	@echo "→ Installed. Open System Settings → Screen Saver to activate."

# Test app — bundled as a proper .app so Bundle.main resolves to the
# Resources/ directory we copy into Contents/Resources/.
testapp:
	@echo "→ Building test app..."
	@rm -rf RainyDayTest.app
	@mkdir -p RainyDayTest.app/Contents/MacOS RainyDayTest.app/Contents/Resources
	swiftc -target arm64-apple-macos14.0 -sdk $(SDK) \
		-framework Cocoa -framework ScreenSaver -framework WebKit \
		-module-name RainyDayTest -Onone \
		$(TESTAPP_SOURCES) -o RainyDayTest.app/Contents/MacOS/RainyDayTest
	cp -R Resources/* RainyDayTest.app/Contents/Resources/
	cp TestApp/Info.plist RainyDayTest.app/Contents/Info.plist
	codesign --force --sign - RainyDayTest.app
	@echo "→ Done: RainyDayTest.app"

run: testapp
	open RainyDayTest.app

icon:
	@echo "→ Generating icon..."
	swift generate_icon.swift
