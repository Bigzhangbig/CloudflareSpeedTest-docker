#!/bin/sh

set -eu

child_pid=""
sleep_pid=""

forward_signal() {
	sig="$1"
	if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
		kill -s "$sig" "$child_pid" 2>/dev/null || true
	fi
	if [ -n "$sleep_pid" ] && kill -0 "$sleep_pid" 2>/dev/null; then
		kill -s "$sig" "$sleep_pid" 2>/dev/null || true
	fi
}

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

# Append default arguments if not provided by the user
args="$@"

# Dynamic IP file and Port based on SCAN_TYPE
SCAN_TYPE="${SCAN_TYPE:-ipv4}"
CFST_TP="${CFST_TP:-}"

if ! echo " $args " | grep -q -- " -f "; then
	case "$SCAN_TYPE" in
		ipv6)
			args="$args -f ipv6.txt"
			if [ -z "$CFST_TP" ]; then CFST_TP="8443"; fi
			;;
		both)
			(cat ip.txt; echo; cat ipv6.txt) > all_ips.txt
			args="$args -f all_ips.txt"
			;;
		*)
			args="$args -f ip.txt"
			;;
	esac
fi

if [ -n "$CFST_TP" ] && ! echo " $args " | grep -q -- " -tp "; then
	args="$args -tp $CFST_TP"
fi

if ! echo " $args " | grep -q -- " -n "; then
	args="$args -n 50"
fi
if ! echo " $args " | grep -q -- " -httping"; then
	args="$args -httping"
fi
if ! echo " $args " | grep -q -- " -dn "; then
	args="$args -dn 20"
fi
if ! echo " $args " | grep -q -- " -sl "; then
	args="$args -sl 0.01"
fi

is_positive_int() {
	value="$1"
	case "$value" in
		''|*[!0-9]*) return 1 ;;
		0) return 1 ;;
		*) return 0 ;;
	esac
}

upload_gist_if_needed() {
	GIST_TOKEN_VALUE="${GIST_TOKEN:-}"
	GIST_ID="${GIST_ID:-}"
	if [ -z "$GIST_TOKEN_VALUE" ] || [ -z "$GIST_ID" ]; then
		echo "[gist] GIST_TOKEN or GIST_ID is empty, skip upload."
		return 0
	fi

	RESULT_FILE="${GIST_RESULT_FILE:-result.csv}"
	if [ ! -f "$RESULT_FILE" ]; then
		echo "[gist] Result file not found: $RESULT_FILE, skip upload."
		return 0
	fi

	GIST_DESCRIPTION_VALUE="${GIST_DESCRIPTION:-}"
	if [ -z "$GIST_DESCRIPTION_VALUE" ]; then
		TEST_PORT=""
		# shellcheck disable=SC2086
		set -- $args
		while [ "$#" -gt 0 ]; do
			if [ "$1" = "-tp" ]; then
				shift
				TEST_PORT="${1:-}"
				break
			fi
			shift
		done
		if [ -z "$TEST_PORT" ]; then
			TEST_PORT="443"
		fi
		GIST_DESCRIPTION_VALUE="CloudflareSpeedTest result [tp=${TEST_PORT}] $(TZ='UTC-8' date '+%Y-%m-%d %H:%M:%S UTC+8')"
	fi
	GIST_DESCRIPTION="$GIST_DESCRIPTION_VALUE"

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
		'{
			description: $description,
			files: {
				($filename): {content: $content}
			}
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
		return 0
	}

	GIST_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty')
	if [ -n "$GIST_URL" ]; then
		echo "[gist] Upload success: $GIST_URL"
	else
		echo "[gist] Upload finished, but no html_url returned."
	fi
	return 0
}

run_once() {
	set +e
	# shellcheck disable=SC2086
	/app/cfst $args &
	child_pid="$!"
	wait "$child_pid"
	cfst_exit=$?
	child_pid=""
	set -e

	if [ "$cfst_exit" -ne 0 ]; then
		echo "[cfst] CFST exited with code $cfst_exit."
		return "$cfst_exit"
	fi

	upload_gist_if_needed
	return 0
}

CFST_LOOP_HOURS="${CFST_LOOP_HOURS:-}"
CFST_LOOP_INTERVAL=""
if [ -n "$CFST_LOOP_HOURS" ]; then
	if is_positive_int "$CFST_LOOP_HOURS"; then
		CFST_LOOP_INTERVAL=$((CFST_LOOP_HOURS * 3600))
		echo "[loop] Enabled. interval=${CFST_LOOP_HOURS}h (${CFST_LOOP_INTERVAL}s)"
	else
		echo "[loop] Invalid CFST_LOOP_HOURS: $CFST_LOOP_HOURS, run once only."
	fi
fi

run_count=1
while :; do
	echo "[loop] Run #$run_count started."
	run_once
	run_status=$?
	if [ "$run_status" -ne 0 ]; then
		exit "$run_status"
	fi

	if [ -z "$CFST_LOOP_INTERVAL" ]; then
		break
	fi

	echo "[loop] Run #$run_count finished. Sleep ${CFST_LOOP_INTERVAL}s before next run."
	sleep "$CFST_LOOP_INTERVAL" &
	sleep_pid="$!"
	wait "$sleep_pid"
	sleep_pid=""
	run_count=$((run_count + 1))
done
