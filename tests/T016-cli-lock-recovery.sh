#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/tests/lib-testing.sh
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/src/sh/littlesecrets.sh

test-start
LS_LOCK_TIMEOUT=0

test-step "Acquire and release an owned lock"
ls_lock_acquire "$TEST_PATH/free.lock"
test-exist "$TEST_PATH/free.lock/pid"
ls_lock_release "$TEST_PATH/free.lock"
test-expect-failure test -e "$TEST_PATH/free.lock"

test-step "Never steal pidless, dead, or live locks"
for holder in '' 999999 "$BASHPID"; do
	lock="$TEST_PATH/existing.lock"
	mkdir "$lock"
	printf '%s\n' "$holder" >"$lock/pid"
	test-expect-failure ls_lock_acquire "$lock"
	test-exist "$lock"
	rm -rf "$lock"
done

test-step "A released lock is not removed again when another holder acquires it"
ls_lock_acquire "$TEST_PATH/reused.lock"
ls_lock_release "$TEST_PATH/reused.lock"
mkdir "$TEST_PATH/reused.lock"
printf '%s\n' another-owner >"$TEST_PATH/reused.lock/token"
ls_lock_release "$TEST_PATH/reused.lock"
test-exist "$TEST_PATH/reused.lock/token"

test-step "A child cannot release its parent's lock"
ls_lock_acquire "$TEST_PATH/parent.lock"
(ls_lock_release "$TEST_PATH/parent.lock")
test-exist "$TEST_PATH/parent.lock/token"
ls_lock_release "$TEST_PATH/parent.lock"

test-end
