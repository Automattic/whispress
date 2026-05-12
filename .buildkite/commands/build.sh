#!/usr/bin/env bash

set -euo pipefail

echo "--- :rubygems: Install gems"
install_gems

# `make dmg` runs `npx appdmg`. The xcode-26.4.1 image doesn't ship Node, so
# install it on demand. `brew install` is a no-op when node is already present.
echo "--- :package: Install Node (for appdmg)"
command -v npx >/dev/null || brew install node

echo "--- :key: Fetch Developer ID certificate"
bundle exec fastlane set_up_signing

echo "--- :hammer: Build, sign, notarize, package"
make release \
	ARCH=universal \
	APP_NAME=WP-Workspace \
	BUNDLE_ID=com.automattic.wpworkspace \
	CODESIGN_IDENTITY="Developer ID Application: Automattic, Inc. (PZYM8XX95Q)"
