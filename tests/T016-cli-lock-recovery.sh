#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/tests/lib-testing.sh
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/src/sh/littlesecrets.sh

# --
# Tests the portable mkdir-based lock used to serialize SSH key derivation:
# grace-window recovery for pidless locks, immediate recovery for dead holders,
# and timeouts (instead of lock stealing) for live holders.

test-start

test-step "Acquire and release a free lock"
test-expect-success ls_lock_acquire "$TEST_PATH/free.lock"
test-exist "$TEST_PATH/free.lock/pid" "Lock directory holds the holder PID"
ls_lock_release "$TEST_PATH/free.lock"
if [ ! -e "$TEST_PATH/free.lock" ]; then
	test-ok "Lock directory removed on release"
else
	test-fail "Lock directory still present after release"
fi

test-step "Pidless lock is reclaimed only after the grace window"
lock="$TEST_PATH/pidless.lock"
mkdir "$lock"
LS_LOCK_GRACE_SECONDS=2
LS_LOCK_MAX_SECONDS=100
LS_LOCK_TIMEOUT=10
start="$(date +%s)"
ls_lock_acquire "$lock"
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -ge 2 ]; then
	test-ok "Waited ${elapsed}s before reclaiming a pidless lock"
else
	test-fail "Reclaimed a pidless lock too early (${elapsed}s)"
fi
ls_lock_release "$lock"

test-step "Dead holder is reclaimed immediately"
lock="$TEST_PATH/dead.lock"
mkdir "$lock"
printf '%s\n' 999999 >"$lock/pid"
LS_LOCK_GRACE_SECONDS=10
LS_LOCK_TIMEOUT=5
start="$(date +%s)"
ls_lock_acquire "$lock"
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -lt 5 ]; then
	test-ok "Dead holder reclaimed immediately (${elapsed}s)"
else
	test-fail "Dead holder not reclaimed promptly (${elapsed}s)"
fi
ls_lock_release "$lock"

test-step "Live holder is not stolen"
lock="$TEST_PATH/live.lock"
mkdir "$lock"
printf '%s\n' "$$" >"$lock/pid"
LS_LOCK_GRACE_SECONDS=1
LS_LOCK_MAX_SECONDS=100
LS_LOCK_TIMEOUT=2
start="$(date +%s)"
if ls_lock_acquire "$lock"; then
	test-fail "Stole a lock held by a live process"
else
	elapsed=$(( $(date +%s) - start ))
	if [ "$elapsed" -ge 2 ]; then
		test-ok "Timed out after ${elapsed}s without stealing the lock"
	else
		test-fail "Returned too early (${elapsed}s)"
	fi
fi
rm -rf "$lock"

test-end

# EOF