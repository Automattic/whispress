#!/bin/sh

set -u

usage() {
	cat <<'EOF'
Usage:
  Tools/wpcom-transcribe.sh --site <site-id-or-domain> --file <audio-file> [--token <bearer-token>]

Required:
  --site <value>          Workspace's WordPress.com site ID or domain.
  --file <path>           Audio file to upload.
  --token <value>         Bearer token. You may also set WPCOM_BEARER_TOKEN.

Optional:
  --intent <value>        dictation or command. Default: dictation.
  --selected-text <text>  Required when --intent command.
  --app-context <json>    Optional JSON string for endpoint app_context.
  --base-url <url>        Default: https://public-api.wordpress.com.
  --auth-header <value>   Exact Authorization header value. Overrides --token.
  --user-agent <value>    User-Agent header. Default: WhisPress/SmokeTest.
  --proxy <url>           Optional curl proxy, e.g. socks5://127.0.0.1:8080.
  --envelope              Add ?_envelope=1 to match the REST proxy/debug tool.
  --verbose               Ask curl to print connection details.

Examples:
  WPCOM_BEARER_TOKEN="$TOKEN" Tools/wpcom-transcribe.sh --site 123456 --file ./sample.mp3
  Tools/wpcom-transcribe.sh --token "$TOKEN" --site example.wordpress.com --file ./sample.mp3
  Tools/wpcom-transcribe.sh --token "$TOKEN" --site 123456 --file ./command.mp3 --intent command --selected-text "Rewrite this."
EOF
}

die() {
	echo "Error: $*" >&2
	echo >&2
	usage >&2
	exit 1
}

need_value() {
	if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
		die "Missing value for $1"
	fi
}

mime_type() {
	case "${1##*.}" in
		flac|FLAC) echo "audio/flac" ;;
		m4a|M4A|mp4|MP4) echo "audio/mp4" ;;
		mp3|MP3|mpeg|MPEG|mpga|MPGA) echo "audio/mpeg" ;;
		ogg|OGG) echo "audio/ogg" ;;
		wav|WAV) echo "audio/wav" ;;
		webm|WEBM) echo "audio/webm" ;;
		*) echo "application/octet-stream" ;;
	esac
}

TOKEN="${WPCOM_BEARER_TOKEN:-}"
SITE=""
FILE=""
INTENT="dictation"
SELECTED_TEXT=""
APP_CONTEXT=""
BASE_URL="https://public-api.wordpress.com"
AUTH_HEADER=""
USER_AGENT="WhisPress/SmokeTest"
PROXY=""
ENVELOPE=""
VERBOSE=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--token)
			need_value "$1" "${2:-}"
			TOKEN="$2"
			shift 2
			;;
		--site)
			need_value "$1" "${2:-}"
			SITE="$2"
			shift 2
			;;
		--file)
			need_value "$1" "${2:-}"
			FILE="$2"
			shift 2
			;;
		--intent)
			need_value "$1" "${2:-}"
			INTENT="$2"
			shift 2
			;;
		--selected-text)
			need_value "$1" "${2:-}"
			SELECTED_TEXT="$2"
			shift 2
			;;
		--app-context)
			need_value "$1" "${2:-}"
			APP_CONTEXT="$2"
			shift 2
			;;
		--base-url)
			need_value "$1" "${2:-}"
			BASE_URL="$2"
			shift 2
			;;
		--auth-header)
			need_value "$1" "${2:-}"
			AUTH_HEADER="$2"
			shift 2
			;;
		--user-agent)
			need_value "$1" "${2:-}"
			USER_AGENT="$2"
			shift 2
			;;
		--proxy)
			need_value "$1" "${2:-}"
			PROXY="$2"
			shift 2
			;;
		--envelope)
			ENVELOPE="1"
			shift
			;;
		--verbose)
			VERBOSE="1"
			shift
			;;
		*)
			die "Unknown argument: $1"
			;;
	esac
done

if [ -z "$TOKEN" ] && [ -z "$AUTH_HEADER" ]; then
	die "Missing --token, --auth-header, or WPCOM_BEARER_TOKEN"
fi
[ -n "$SITE" ] || die "Missing --site"
[ -n "$FILE" ] || die "Missing --file"
[ -f "$FILE" ] || die "Audio file not found: $FILE"

case "$INTENT" in
	dictation|command) ;;
	*) die "--intent must be dictation or command" ;;
esac

if [ "$INTENT" = "command" ] && [ -z "$SELECTED_TEXT" ]; then
	die "--selected-text is required when --intent command"
fi

if [ -n "$AUTH_HEADER" ]; then
	AUTHORIZATION="$AUTH_HEADER"
else
	case "$TOKEN" in
		[Bb][Ee][Aa][Rr][Ee][Rr]\ *|[Xx]-[Ww][Pp][Tt][Oo][Kk][Ee][Nn]\ *) AUTHORIZATION="$TOKEN" ;;
		*) AUTHORIZATION="Bearer $TOKEN" ;;
	esac
fi

BASE_URL="${BASE_URL%/}"
URL="$BASE_URL/wpcom/v2/sites/$SITE/ai/transcription"
if [ -n "$ENVELOPE" ]; then
	URL="$URL?_envelope=1"
fi
AUDIO_FORM="audio_file=@$FILE;type=$(mime_type "$FILE")"
CURL_FLAGS="-sS --connect-timeout 15 --max-time 120"
if [ -n "$VERBOSE" ]; then
	CURL_FLAGS="-v --connect-timeout 15 --max-time 120"
fi
if [ -n "$PROXY" ]; then
	export HTTPS_PROXY="$PROXY"
	export https_proxy="$PROXY"
fi

if [ -n "$SELECTED_TEXT" ] && [ -n "$APP_CONTEXT" ]; then
	curl $CURL_FLAGS -X POST "$URL" \
		-H "Authorization: $AUTHORIZATION" \
		-A "$USER_AGENT" \
		-F "$AUDIO_FORM" \
		--form-string "intent=$INTENT" \
		--form-string "client=whispress-sh" \
		--form-string "client_version=dev" \
		--form-string "selected_text=$SELECTED_TEXT" \
		--form-string "app_context=$APP_CONTEXT"
elif [ -n "$SELECTED_TEXT" ]; then
	curl $CURL_FLAGS -X POST "$URL" \
		-H "Authorization: $AUTHORIZATION" \
		-A "$USER_AGENT" \
		-F "$AUDIO_FORM" \
		--form-string "intent=$INTENT" \
		--form-string "client=whispress-sh" \
		--form-string "client_version=dev" \
		--form-string "selected_text=$SELECTED_TEXT"
elif [ -n "$APP_CONTEXT" ]; then
	curl $CURL_FLAGS -X POST "$URL" \
		-H "Authorization: $AUTHORIZATION" \
		-A "$USER_AGENT" \
		-F "$AUDIO_FORM" \
		--form-string "intent=$INTENT" \
		--form-string "client=whispress-sh" \
		--form-string "client_version=dev" \
		--form-string "app_context=$APP_CONTEXT"
else
	curl $CURL_FLAGS -X POST "$URL" \
		-H "Authorization: $AUTHORIZATION" \
		-A "$USER_AGENT" \
		-F "$AUDIO_FORM" \
		--form-string "intent=$INTENT" \
		--form-string "client=whispress-sh" \
		--form-string "client_version=dev"
fi

echo
