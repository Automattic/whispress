#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  Tools/verify-oauth-secret.sh <app-bundle>

Reads WPCOMOAuthClientSecret from the bundle's Info.plist and exits
non-zero if it is missing or empty. Run after the build that injects
the secret to catch misconfigured release builds before they ship.
EOF
}

if [ "$#" -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	usage
	exit 64
fi

APP_BUNDLE="$1"
PLIST="$APP_BUNDLE/Contents/Info.plist"

if [ ! -f "$PLIST" ]; then
	echo "Error: $PLIST not found." >&2
	exit 1
fi

# Command substitution strips the trailing newline plutil emits, so [ -z ] gives
# the right answer for both the unset-key and empty-string cases.
secret=$(plutil -extract WPCOMOAuthClientSecret raw -o - "$PLIST" 2>/dev/null || true)
if [ -z "$secret" ]; then
	echo "Error: $APP_BUNDLE is missing WPCOMOAuthClientSecret in Info.plist." >&2
	echo "Set WPCOM_OAUTH_CLIENT_SECRET or pass WPCOM_OAUTH_CLIENT_SECRET_FILE before building." >&2
	exit 1
fi
