#!/bin/sh

set -eu

usage() {
	cat <<'EOF'
Usage:
  Tools/manual-release.sh [--publish]

Builds and packages a local WP Workspace release zip.

Options:
  --publish                    Push the version tag and create a GitHub Release.
  --repo <owner/name>           GitHub repository. Default: Automattic/workspace-osx.
  --version <version>           Version to release. Default: Info.plist CFBundleShortVersionString.
  --notes <text>                Release notes used with --publish.
  --notes-file <path>           Release notes file used with --publish.
  --secret-file <path>          File containing WPCOM OAuth client secret.
  --codesign-identity <value>   Code signing identity. Default: - (ad-hoc).
  --allow-dirty                 Allow releasing from a dirty worktree.
  -h, --help                    Show this help.

Required:
  Set WPCOM_OAUTH_CLIENT_SECRET, or pass --secret-file.

Examples:
  WPCOM_OAUTH_CLIENT_SECRET="$WPCOM_CLIENT_SECRET" Tools/manual-release.sh
  Tools/manual-release.sh --secret-file .wpcom-oauth-client-secret --publish
EOF
}

die() {
	echo "Error: $*" >&2
	exit 1
}

need_value() {
	if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
		die "Missing value for $1"
	fi
}

PUBLISH=0
REPO="${GITHUB_REPOSITORY:-Automattic/workspace-osx}"
VERSION=""
NOTES="First WordPress Workspace preview release."
NOTES_FILE=""
SECRET_FILE=""
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ALLOW_DIRTY=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--publish)
			PUBLISH=1
			shift
			;;
		--repo)
			need_value "$1" "${2:-}"
			REPO="$2"
			shift 2
			;;
		--version)
			need_value "$1" "${2:-}"
			VERSION="$2"
			shift 2
			;;
		--notes)
			need_value "$1" "${2:-}"
			NOTES="$2"
			shift 2
			;;
		--notes-file)
			need_value "$1" "${2:-}"
			NOTES_FILE="$2"
			shift 2
			;;
		--secret-file)
			need_value "$1" "${2:-}"
			SECRET_FILE="$2"
			shift 2
			;;
		--codesign-identity)
			need_value "$1" "${2:-}"
			CODESIGN_IDENTITY="$2"
			shift 2
			;;
		--allow-dirty)
			ALLOW_DIRTY=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1"
			;;
	esac
done

command -v git >/dev/null 2>&1 || die "git is required"
command -v make >/dev/null 2>&1 || die "make is required"
command -v ditto >/dev/null 2>&1 || die "ditto is required"
command -v plutil >/dev/null 2>&1 || die "plutil is required"
command -v codesign >/dev/null 2>&1 || die "codesign is required"

if [ "$ALLOW_DIRTY" -ne 1 ] && [ -n "$(git status --porcelain)" ]; then
	die "Working tree is dirty. Commit first or pass --allow-dirty."
fi

if [ -z "$VERSION" ]; then
	VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
fi

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
if [ "$VERSION" != "$PLIST_VERSION" ]; then
	die "Requested version $VERSION does not match Info.plist version $PLIST_VERSION."
fi

if [ -n "$SECRET_FILE" ]; then
	[ -f "$SECRET_FILE" ] || die "Secret file not found: $SECRET_FILE"
	export WPCOM_OAUTH_CLIENT_SECRET_FILE="$SECRET_FILE"
	unset WPCOM_OAUTH_CLIENT_SECRET || true
elif [ -z "${WPCOM_OAUTH_CLIENT_SECRET:-}" ]; then
	die "Set WPCOM_OAUTH_CLIENT_SECRET or pass --secret-file."
else
	export WPCOM_OAUTH_CLIENT_SECRET
	unset WPCOM_OAUTH_CLIENT_SECRET_FILE || true
fi

TAG="v$VERSION"
APP_PATH="build/WP Workspace.app"
ZIP_PATH="build/WPWorkspace-$VERSION.zip"

echo "Building WP Workspace $VERSION..."
make clean
make \
	ARCH=universal \
	APP_NAME="WP Workspace" \
	BUNDLE_ID=com.automattic.wpworkspace \
	CODESIGN_IDENTITY="$CODESIGN_IDENTITY"

echo "Verifying app..."
codesign --verify --deep --strict "$APP_PATH"
SECRET_LENGTH=$(plutil -extract WPCOMOAuthClientSecret raw -o - "$APP_PATH/Contents/Info.plist" | wc -c | tr -d ' ')
if [ "$SECRET_LENGTH" -eq 0 ]; then
	die "Built app is missing WPCOMOAuthClientSecret."
fi

echo "Packaging $ZIP_PATH..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created $ZIP_PATH"

if [ "$PUBLISH" -eq 0 ]; then
	cat <<EOF

Release package is ready.
To publish it later, rerun this script with --publish and the same secret input.

Or upload this file manually in GitHub Releases:
  $ZIP_PATH
EOF
	exit 0
fi

command -v gh >/dev/null 2>&1 || die "gh is required for --publish"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
	die "GitHub Release $TAG already exists."
fi

if git rev-parse "$TAG^{commit}" >/dev/null 2>&1; then
	if [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
		die "Tag $TAG exists but does not point at HEAD."
	fi
else
	git tag -a "$TAG" -m "WP Workspace $VERSION"
fi

git push origin "$TAG"

if [ -n "$NOTES_FILE" ]; then
	gh release create "$TAG" "$ZIP_PATH" \
		--repo "$REPO" \
		--title "WP Workspace $VERSION" \
		--notes-file "$NOTES_FILE"
else
	gh release create "$TAG" "$ZIP_PATH" \
		--repo "$REPO" \
		--title "WP Workspace $VERSION" \
		--notes "$NOTES"
fi

echo "Published WP Workspace $VERSION:"
gh release view "$TAG" --repo "$REPO" --json url --jq '.url'
