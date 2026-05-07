<p align="center">
  <img src="Resources/AppIcon-Source.png" alt="WhisPress app icon" width="160" height="160">
</p>

<h1 align="center">WhisPress</h1>

<p align="center">
  <strong>macOS dictation, powered by WordPress.com.</strong>
</p>

WhisPress is a macOS menu bar dictation app in the spirit of SuperWhisper and
Monologue, but built around WordPress.com. It records audio locally, sends it to
the WordPress.com cloud, and pastes the returned text wherever your cursor is.

WhisPress comes with your WordPress.com subscription and uses Content Guidelines
to store your transcription configuration. Pick a WordPress.com workspace, edit
that workspace's `Transcribe` guideline, and WhisPress will use it for spelling,
cleanup, formatting, and dictation behavior.

[Download WhisPress from GitHub Releases](https://github.com/Automattic/whispress/releases)

## Why

- All agents and apps can use a single source of truth for spelling and style.
- You can share transcription configuration with your team by sharing the
  WordPress.com workspace.
- WordPress.com handles the cloud AI work behind the scenes.

## How It Works

WhisPress is a thin client:

- Sign in with WordPress.com.
- Choose the workspace whose transcription guideline should be used.
- Record with a shortcut, then WhisPress calls the workspace's WordPress.com
  transcription endpoint and pastes the result.

There is no local provider setup, API key entry, model picker, prompt editor, or
spelling editor in the Mac app. Configuration lives on WordPress.com, where it can
be shared, audited, and reused by other clients.

## WordPress.com Guidelines

Each selected workspace is backed by a WordPress.com site that can provide a
native `wp_guideline` skill with the slug `transcribe`. The WordPress.com
transcription endpoint loads that skill server-side and uses it as the
transcription prompt.

Switching workspaces changes the active transcription configuration. Editing the
guideline on WordPress.com changes what WhisPress uses the next time it
transcribes.

## Open Source

WhisPress is a fork of
[FreeFlow](https://github.com/zachlatta/freeflow), a great open source macOS
dictation app. The fork reworks the app into a WordPress.com-branded thin client.

## Build From Source

```sh
make
```

The default development bundle is `WhisPress Dev.app` with bundle identifier
`com.automattic.whispress.dev`.

### WordPress.com OAuth

WhisPress uses a registered native WordPress.com OAuth app with:

- Redirect URI: `whispress://oauth/callback`
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

That builds a universal `WhisPress.app`, verifies that the WordPress.com OAuth
client secret was injected, and creates:

```text
build/WhisPress-0.2.1.zip
```

Inspect the zip before publishing. When it is ready, publish the GitHub Release:

```sh
Tools/manual-release.sh --secret-file .wpcom-oauth-client-secret \
  --publish \
  --notes "First WhisPress preview release."
```

The script uses the version from `Info.plist`, creates or reuses the matching
`vX.Y.Z` tag, pushes the tag, and uploads the zip to
[GitHub Releases](https://github.com/Automattic/whispress/releases). By default
it uses ad-hoc signing; pass `--codesign-identity` when a Developer ID signing
identity is ready.

## Endpoint Smoke Test

You can test the WordPress.com transcription endpoint directly with a bearer
token, workspace, and audio file:

```sh
WPCOM_BEARER_TOKEN="$TOKEN" Tools/wpcom-transcribe.sh \
  --site 123456 \
  --file /path/to/audio.mp3
```

The script does not perform OAuth. It posts multipart audio to:

```text
POST /wpcom/v2/sites/{site}/ai/transcription
```
