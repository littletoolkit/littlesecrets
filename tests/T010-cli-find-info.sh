#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Create nested repositories"
mkdir -p "$TEST_PATH/.littlesecrets/secret/outer.secret"
mkdir -p "$TEST_PATH/repo/.littlesecrets/secret/inner.secret"
touch "$TEST_PATH/.littlesecrets/secret/outer.secret/secret.enc"
touch "$TEST_PATH/.littlesecrets/secret/outer.secret/user@host.key"
touch "$TEST_PATH/repo/.littlesecrets/secret/inner.secret/secret.enc"
touch "$TEST_PATH/repo/.littlesecrets/secret/inner.secret/user@host.key"
mkdir -p "$TEST_PATH/repo/child"
cd "$TEST_PATH/repo/child" || exit 1

test-step "Find matching secrets in all repositories"
FIND_OUTPUT="$(ls_cli find '*secret')"
echo "$FIND_OUTPUT" | grep -q "inner.secret: $TEST_PATH/repo/.littlesecrets" || test-fail "find should include the nearest repository"
echo "$FIND_OUTPUT" | grep -q "outer.secret: $TEST_PATH/.littlesecrets" || test-fail "find should include the ancestor repository"

test-step "Reject unmatched find"
if ls_cli find missing-secret >/dev/null 2>&1; then
	test-fail "find should fail when no secret matches"
fi

test-step "Show other repositories in text info"
INFO_OUTPUT="$(ls_cli info)"
echo "$INFO_OUTPUT" | grep -q "Path: $TEST_PATH/repo/.littlesecrets" || test-fail "info should show the current repository"
echo "$INFO_OUTPUT" | grep -q "Repositories: $TEST_PATH/.littlesecrets" || test-fail "info should show other repositories"

test-step "Show other repositories in JSON info"
JSON_OUTPUT="$(ls_cli -f json info)"
echo "$JSON_OUTPUT" | grep -q '"repositories": \["' || test-fail "JSON info should contain repositories"
echo "$JSON_OUTPUT" | grep -q "$TEST_PATH/.littlesecrets" || test-fail "JSON info should contain the ancestor repository"
