<p align="center">
  <img src="Resources/AppIcon-Source.png" alt="WordPress Workspace app icon" width="160" height="160">
</p>

<h1 align="center">WordPress Workspace</h1>

<p align="center">
  <strong>Turn your WordPress.com site into a workspace on your Mac.</strong>
</p>

WordPress Workspace brings your WordPress.com site to the macOS menu bar. Ask
the WordPress Agent, capture screenshots, upload images, transform selected text,
and dictate when voice is the fastest way to get words down.

[Download WordPress Workspace from GitHub Releases](https://github.com/Automattic/workspace/releases)

## Why

- Your WordPress.com site becomes the place your Mac work can land.
- Screenshots, uploads, selected text, and voice input can all flow into the
  same WordPress Agent context.
- Content Guidelines give your site a shared source of truth for transcription
  cleanup, spelling, formatting, and style.
- WordPress.com handles the cloud AI work behind the scenes.

## How It Works

WordPress Workspace is a thin Mac client:

- Sign in with WordPress.com.
- Choose the site you want to work with.
- Ask the WordPress Agent, capture a screenshot, upload images, transform
  selected text, or dictate text from anywhere on your Mac.

There is no local provider setup, API key entry, model picker, prompt editor, or
spelling editor in the Mac app. Configuration lives on WordPress.com, where it
can be shared, audited, and reused by other clients.

## WordPress.com Guidelines

The selected site can provide a native `wp_guideline` skill with the slug
`transcribe`. The WordPress.com transcription endpoint loads that skill
server-side and uses it as the transcription prompt.

Switching sites changes the active transcription configuration. Editing the
guideline on WordPress.com changes what WordPress Workspace uses the next time
you dictate or transform selected text.

## Open Source

WordPress Workspace is a fork of
[FreeFlow](https://github.com/zachlatta/freeflow), a great open source macOS
dictation app. The fork reworks the app into a WordPress.com site workspace for
Agent chat, screenshots, uploads, selected text, and voice input.

## Build From Source

```sh
make
```

The default development bundle is `WP Workspace Dev.app` with bundle identifier
`com.automattic.wpworkspace.dev`.

### WordPress.com OAuth

WordPress Workspace uses a registered native WordPress.com OAuth app with:

- Redirect URI: `wpworkspace://oauth/callback`
- Authorize URL: `https://public-api.wordpress.com/oauth2/authorize`
- Token URL: `https://public-api.wordpress.com/oauth2/token`

The OAuth client ID is committed in `Info.plist`. The client secret is not
committed; inject it when building locally or packaging a release:

```sh
WPCOM_OAUTH_CLIENT_SECRET="$WPCOM_CLIENT_SECRET" make CODESIGN_IDENTITY=-
```

Or read it from an untracked local file:

```sh
make CODESIGN_IDENTITY=- WPCOM_OAUTH_CLIENT_SECRET_FILE=.wpcom-oauth-client-secret
```

For local development with a different WordPress.com OAuth app, pass that app's
client ID at build time instead of editing `Info.plist`:

```sh
make CODESIGN_IDENTITY=- \
  WPCOM_OAUTH_CLIENT_ID="$WPCOM_CLIENT_ID" \
  WPCOM_OAUTH_CLIENT_SECRET_FILE=.wpcom-oauth-client-secret
```

The secret is copied into the built app bundle and then the app is signed. This
is an app credential rather than a server-grade secret, because native app
bundles can be inspected. Do not commit it, and rotate it if it leaks publicly.

## Manual Release

GitHub Actions release automation is present but intentionally parked until the
signing, notarization, and release-channel setup is finalized. For now, make
releases locally from a clean working tree:

```sh
Tools/manual-release.sh --secret-file .wpcom-oauth-client-secret
```

That builds a universal `WP Workspace.app`, verifies that the WordPress.com
OAuth client secret was injected, and creates:

```text
build/WPWorkspace-0.3.0.zip
```

Inspect the zip before publishing. When it is ready, publish the GitHub Release:

```sh
Tools/manual-release.sh --secret-file .wpcom-oauth-client-secret \
  --publish \
  --notes "First WordPress Workspace preview release."
```

The script uses the version from `Info.plist`, creates or reuses the matching
`vX.Y.Z` tag, pushes the tag, and uploads the zip to
[GitHub Releases](https://github.com/Automattic/workspace/releases). By
default it uses ad-hoc signing; pass `--codesign-identity` when a Developer ID
signing identity is ready.

## Endpoint Smoke Test

You can test the WordPress.com transcription endpoint directly with a bearer
token, site, and audio file:

```sh
WPCOM_BEARER_TOKEN="$TOKEN" Tools/wpcom-transcribe.sh \
  --site 123456 \
  --file /path/to/audio.mp3
```

The script does not perform OAuth. It posts multipart audio to:

```text
POST /wpcom/v2/sites/{site}/ai/transcription
```
