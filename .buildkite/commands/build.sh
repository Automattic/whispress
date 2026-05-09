#!/usr/bin/env bash

set -euo pipefail

echo "--- :rubygems: Install gems"
install_gems

echo "--- :key: Fetch Developer ID certificate"
bundle exec fastlane set_up_signing

echo "--- :hammer: Build app (universal, ad-hoc signed)"
make ARCH=universal CODESIGN_IDENTITY=-

echo "--- :package: Zip artifact"
app_bundle=$(ls -d build/*.app | head -1)
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "${app_bundle%.app}.zip"
