# WhisPress

WhisPress is a macOS menu bar dictation client for WordPress.com.

It records local audio, authenticates with WordPress.com, sends the recording to the selected site's generic `/ai/transcription` endpoint, and pastes the returned text at the cursor.

## Current Shape

- WordPress.com OAuth sign-in with the native `whispress://oauth/callback` scheme.
- Per-site configuration by selecting a WordPress.com site.
- Server-side transcription behavior through the selected site's native `wp_guideline` skill with slug `transcribe`.
- Thin client UI: account, site picker, shortcuts, microphone, paste behavior, voice macros, and run history.
- No local API keys, provider URLs, model selection, prompt editing, spelling editing, or guideline editing.

## Build

```sh
make
```

The default development bundle is `WhisPress Dev.app` with bundle identifier `com.automattic.whispress.dev`.

## WordPress.com OAuth

WhisPress uses the classic registered WordPress.com OAuth app flow:

- Authorization endpoint: `https://public-api.wordpress.com/oauth2/authorize`
- Token endpoint: `https://public-api.wordpress.com/oauth2/token`
- Redirect URI: `whispress://oauth/callback`

Set `WPCOMOAuthClientID` and `WPCOMOAuthClientSecret` in `Info.plist` from a WordPress.com application registered with that redirect URI. This flow exchanges the authorization code with the client secret and uses the returned long-lived bearer token for API calls.

The client ID is public and is committed in `Info.plist`. The client secret is intentionally blank in source. For local testing, inject it at build time:

```sh
WPCOM_OAUTH_CLIENT_SECRET="$WPCOM_CLIENT_SECRET" make CODESIGN_IDENTITY=-
```

You can also keep the secret in an untracked local file and point the build at it:

```sh
make CODESIGN_IDENTITY=- WPCOM_OAUTH_CLIENT_SECRET_FILE=.wpcom-oauth-client-secret
```

The Makefile copies `Info.plist`, writes `WPCOMOAuthClientSecret` into the built app bundle, and then signs the app. This post-build credential step runs every time `make` runs, even when Swift sources are already up to date. This client secret is not a server-grade secret once it ships inside a native app bundle; it can be extracted by someone determined. We still use it because WordPress.com's classic OAuth token endpoint requires it for registered apps, and this flow gives the long-lived token behavior WhisPress wants. Treat the secret as an app credential: do not commit it, inject it during local/release packaging, and rotate it if it leaks publicly.

## Endpoint Smoke Test

Call the WordPress.com AI transcription endpoint with a bearer token, site, and audio file:

```sh
WPCOM_BEARER_TOKEN="$TOKEN" Tools/wpcom-transcribe.sh \
  --site 123456 \
  --file /path/to/audio.mp3
```

You can generate a tiny supported sample file locally with macOS built-ins:

```sh
say "Testing WhisPress transcription through WordPress dot com." -o /tmp/whispress-test.aiff
afconvert /tmp/whispress-test.aiff /tmp/whispress-test.m4a -f m4af -d aac
```

Command mode is also supported:

```sh
Tools/wpcom-transcribe.sh \
  --token "$TOKEN" \
  --site example.wordpress.com \
  --file /path/to/command.mp3 \
  --intent command \
  --selected-text "Rewrite this sentence."
```

The script does not perform OAuth. It only posts multipart audio to `POST /wpcom/v2/sites/{site}/ai/transcription` with `curl` and prints the JSON response.
