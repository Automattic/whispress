# APP_NAME controls the .app bundle folder; PRODUCT_NAME controls the executable and plist identity.
APP_NAME ?= WP Workspace Dev
PRODUCT_NAME ?= WP Workspace
BUNDLE_ID ?= com.automattic.wpworkspace.dev
WPCOM_OAUTH_CLIENT_SECRET_FILE ?=
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
CODESIGN_IDENTITY ?= -
CONTENTS = $(APP_BUNDLE)/Contents
MACOS_DIR = $(CONTENTS)/MacOS
empty :=
space := $(empty) $(empty)
APP_EXECUTABLE = $(MACOS_DIR)/$(PRODUCT_NAME)
APP_EXECUTABLE_TARGET := $(subst $(space),\ ,$(APP_EXECUTABLE))
ZIP_PATH = $(BUILD_DIR)/$(APP_NAME).zip
DMG_PATH = $(BUILD_DIR)/$(APP_NAME).dmg
NOTARIZE = Tools/notarize.sh

SOURCES = $(shell find Sources -name '*.swift' -type f | LC_ALL=C sort)
RESOURCES = $(CONTENTS)/Resources
ARCH ?= $(shell uname -m)
ICON_SOURCE = Resources/AppIcon-Source.png
ICON_ICNS = Resources/AppIcon.icns
WPCOM_LOGO = Resources/WPCOM-Blueberry-Pill-Logo.svg
MENU_BAR_LOGO = Resources/MenuBarWordPressLogo.svg
FONT_RESOURCES = $(shell find Resources/Fonts -type f 2>/dev/null | LC_ALL=C sort)

.PHONY: all clean run icon dmg codesign-dmg notarize-app notarize-dmg zip release

all: $(APP_EXECUTABLE_TARGET)

$(APP_EXECUTABLE_TARGET): $(SOURCES) Info.plist $(ICON_ICNS) $(ICON_SOURCE) $(WPCOM_LOGO) $(MENU_BAR_LOGO) $(FONT_RESOURCES)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES)"
ifeq ($(ARCH),universal)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(PRODUCT_NAME)-arm64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target arm64-apple-macosx13.0 \
		$(SOURCES)
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(PRODUCT_NAME)-x86_64" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target x86_64-apple-macosx13.0 \
		$(SOURCES)
	lipo -create -output "$(MACOS_DIR)/$(PRODUCT_NAME)" \
		"$(MACOS_DIR)/$(PRODUCT_NAME)-arm64" \
		"$(MACOS_DIR)/$(PRODUCT_NAME)-x86_64"
	@rm "$(MACOS_DIR)/$(PRODUCT_NAME)-arm64" "$(MACOS_DIR)/$(PRODUCT_NAME)-x86_64"
else
	swiftc \
		-parse-as-library \
		-o "$(MACOS_DIR)/$(PRODUCT_NAME)" \
		-sdk $(shell xcrun --show-sdk-path) \
		-target $(ARCH)-apple-macosx13.0 \
		$(SOURCES)
endif
	@cp Info.plist "$(CONTENTS)/"
	@plutil -replace CFBundleName -string "$(PRODUCT_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleDisplayName -string "$(PRODUCT_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleExecutable -string "$(PRODUCT_NAME)" "$(CONTENTS)/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS)/Info.plist"
	@cp $(ICON_ICNS) "$(RESOURCES)/"
	@cp $(ICON_SOURCE) "$(RESOURCES)/"
	@cp $(WPCOM_LOGO) "$(RESOURCES)/"
	@cp $(MENU_BAR_LOGO) "$(RESOURCES)/"
	@rm -rf "$(RESOURCES)/Fonts"
	@cp -R Resources/Fonts "$(RESOURCES)/Fonts"
	@secret="$${WPCOM_OAUTH_CLIENT_SECRET:-}"; \
		if [ -n "$(WPCOM_OAUTH_CLIENT_SECRET_FILE)" ]; then \
			secret="$$(cat "$(WPCOM_OAUTH_CLIENT_SECRET_FILE)")"; \
		fi; \
		plutil -replace WPCOMOAuthClientSecret -string "$$secret" "$(CONTENTS)/Info.plist"
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" --entitlements WPWorkspace.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

icon: $(ICON_ICNS)

$(ICON_ICNS): $(ICON_SOURCE)
	@mkdir -p $(BUILD_DIR)/AppIcon.iconset
	@sips -z 16 16 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_16x16@2x.png > /dev/null
	@sips -z 32 32 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32.png > /dev/null
	@sips -z 64 64 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_32x32@2x.png > /dev/null
	@sips -z 128 128 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_128x128@2x.png > /dev/null
	@sips -z 256 256 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_256x256@2x.png > /dev/null
	@sips -z 512 512 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512.png > /dev/null
	@sips -z 1024 1024 $< --out $(BUILD_DIR)/AppIcon.iconset/icon_512x512@2x.png > /dev/null
	@iconutil -c icns -o $@ $(BUILD_DIR)/AppIcon.iconset
	@rm -rf $(BUILD_DIR)/AppIcon.iconset
	@echo "Generated $@"

dmg: all
	@rm -f "$(DMG_PATH)"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@mkdir -p $(BUILD_DIR)/dmg-staging
	@cp -R "$(APP_BUNDLE)" $(BUILD_DIR)/dmg-staging/
	@osascript -e 'tell application "Finder" to make alias file to POSIX file "/Applications" at POSIX file "'"$$(cd $(BUILD_DIR)/dmg-staging && pwd)"'"'
	@ALIAS=$$(find $(BUILD_DIR)/dmg-staging -maxdepth 1 -not -name '*.app' -not -name '.DS_Store' -type f | head -1) && mv "$$ALIAS" "$(BUILD_DIR)/dmg-staging/Applications"
	@fileicon set "$(BUILD_DIR)/dmg-staging/Applications" /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns
	@echo "Creating DMG..."
	@create-dmg \
		--volname "$(APP_NAME)" \
		--volicon "$(ICON_ICNS)" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 128 \
		--icon "$(APP_NAME).app" 180 170 \
		--hide-extension "$(APP_NAME).app" \
		--icon "Applications" 480 170 \
		--no-internet-enable \
		"$(DMG_PATH)" \
		"$(BUILD_DIR)/dmg-staging"
	@rm -rf $(BUILD_DIR)/dmg-staging
	@echo "Created $(DMG_PATH)"

codesign-dmg: dmg
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(DMG_PATH)"

# Notarize the .app in place. Stapling rewrites the bundle, so any
# subsequent `codesign --force` on it would strip the ticket — keep
# this step at the very end of the build chain for the .app.
notarize-app: $(APP_EXECUTABLE_TARGET)
	$(NOTARIZE) "$(APP_BUNDLE)"

# ZIP the (already stapled) .app for direct distribution alongside the DMG.
zip: notarize-app
	@rm -f "$(ZIP_PATH)"
	@ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(ZIP_PATH)"
	@echo "Created $(ZIP_PATH)"

notarize-dmg: codesign-dmg
	$(NOTARIZE) "$(DMG_PATH)"

# Full release: notarize+staple .app, ZIP it, build+sign+notarize+staple DMG.
# Order matters: zip pulls in notarize-app; notarize-dmg pulls in dmg, which
# stages the (already stapled) .app into the DMG before the DMG itself is
# signed and notarized.
release: zip notarize-dmg
	@echo "Release artifacts:"
	@echo "  $(ZIP_PATH)"
	@echo "  $(DMG_PATH)"

clean:
	rm -rf $(BUILD_DIR)

run: all
	open "$(APP_BUNDLE)"
