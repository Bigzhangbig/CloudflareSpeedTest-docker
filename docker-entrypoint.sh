#!/bin/sh

set -eu

set +e
/app/cfst "$@"
cfst_exit=$?
set -e

if [ "$cfst_exit" -ne 0 ]; then
	echo "[gist] CFST exited with code $cfst_exit, skip gist upload."
	exit "$cfst_exit"
fi

GIST_TOKEN_VALUE="${GIST_TOKEN:-}"
GIST_ID="${GIST_ID:-}"
if [ -z "$GIST_TOKEN_VALUE" ] || [ -z "$GIST_ID" ]; then
	echo "[gist] GIST_TOKEN or GIST_ID is empty, skip upload."
	exit 0
fi

RESULT_FILE="${GIST_RESULT_FILE:-result.csv}"
if [ ! -f "$RESULT_FILE" ]; then
	echo "[gist] Result file not found: $RESULT_FILE, skip upload."
	exit 0
fi

GIST_DESCRIPTION="${GIST_DESCRIPTION:-CloudflareSpeedTest result $(TZ='UTC-8' date '+%Y-%m-%d %H:%M:%S UTC+8')}"

GIST_META=$(curl -fsSL \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer $GIST_TOKEN_VALUE" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"https://api.github.com/gists/$GIST_ID" 2>/dev/null || echo '{}')

GIST_FILENAME="${GIST_FILENAME:-}"
if [ -z "$GIST_FILENAME" ]; then
	GIST_FILENAME=$(echo "$GIST_META" | jq -r '.files | keys[0] // "result.csv"')
fi

PAYLOAD=$(jq -n \
	--arg filename "$GIST_FILENAME" \
	--arg description "$GIST_DESCRIPTION" \
	--arg content "$(cat "$RESULT_FILE")" \
	--argjson existing "$GIST_META" \
	'{
		description: $description,
		files: (
			((($existing.files // {}) | to_entries | map(if .key == $filename then empty else {key: .key, value: null} end) | from_entries)
			+ {($filename): {content: $content}}
			)
		)
	}')

UPLOAD_URL="https://api.github.com/gists/$GIST_ID"
UPLOAD_METHOD="PATCH"

RESPONSE=$(curl -fsSL -X "$UPLOAD_METHOD" \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer $GIST_TOKEN_VALUE" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"$UPLOAD_URL" \
	-d "$PAYLOAD") || {
	echo "[gist] Upload failed."
	exit 0
}

GIST_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty')
if [ -n "$GIST_URL" ]; then
	echo "[gist] Upload success: $GIST_URL"
else
	echo "[gist] Upload finished, but no html_url returned."
fi
