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
