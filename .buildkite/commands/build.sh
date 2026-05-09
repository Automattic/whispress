#!/usr/bin/env bash

set -euo pipefail

echo "--- :rubygems: Install gems"
install_gems

echo "--- :package: Install brew dependencies"
brew install create-dmg fileicon

echo "--- :key: Fetch Developer ID certificate"
bundle exec fastlane set_up_signing

echo "--- :hammer: Build, sign, notarize, zip"
# `make zip` notarizes and staples the .app, then ditto-zips it.
# DMG packaging is skipped on CI for now: the `dmg` recipe drives Finder via
# osascript to create an Applications alias, which times out on headless agents.
make zip \
	ARCH=universal \
	APP_NAME="WP Workspace" \
	BUNDLE_ID=com.automattic.wpworkspace \
	CODESIGN_IDENTITY="Developer ID Application: Automattic, Inc. (PZYM8XX95Q)"
