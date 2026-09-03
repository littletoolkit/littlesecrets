#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Init store and register additional test user"
ls_store_init || test-fail "Could not init store"
BOB_KEY="$PWD/bob.rsa"
ssh-keygen -t rsa -b 4096 -N "" -f "$BOB_KEY" -C "bob@machine" 2>/dev/null
ls_cli register "bob@machine" "${BOB_KEY}.pub" || test-fail "Could not register bob"

test-step "Create legacy v1 secret with multiple recipients"
SECRET_TEXT="Payload to be upgraded from v1 to v2"
echo -n "$SECRET_TEXT" | ls_cli --v1 add legacy.secret || test-fail "Could not add legacy secret"
ls_cli grant legacy.secret "bob@machine" || test-fail "Could not grant legacy secret to bob"

test-step "Confirm format is v1 initially"
test-expect "$(ls_secret_format_version legacy.secret)" "v1" "Initially v1 format"
test-expect "$(ls_cli -k "$BOB_KEY" -u "bob@machine" get legacy.secret)" "$SECRET_TEXT" "Bob reads v1 secret"
test-expect "$(ls_cli get legacy.secret)" "$SECRET_TEXT" "Primary user reads v1 secret"

test-step "Run upgrade command on v1 secret"
UPGRADE_OUT="$(ls_cli upgrade legacy.secret)"
test-substring "$UPGRADE_OUT" "Upgraded"

test-step "Verify format has transitioned to v2 (Encrypt-then-MAC)"
test-expect "$(ls_secret_format_version legacy.secret)" "v2" "Format successfully updated to v2"
test-substring "$(cat .littlesecrets/secret/legacy.secret/secret.hmac)" "v2:etm:"

test-step "Verify all recipients retain access after upgrade"
test-expect "$(ls_cli get legacy.secret)" "$SECRET_TEXT" "Primary user reads upgraded v2 secret"
test-expect "$(ls_cli -k "$BOB_KEY" -u "bob@machine" get legacy.secret)" "$SECRET_TEXT" "Bob reads upgraded v2 secret"

test-step "Verify integrity verification passes on upgraded secret"
test-expect-success ls_cli verify legacy.secret

test-step "Upgrading already up-to-date secret is safe and no-op"
REUPGRADE_OUT="$(ls_cli upgrade legacy.secret)"
test-substring "$REUPGRADE_OUT" "Already"

rm -f "$BOB_KEY" "${BOB_KEY}.pub"

test-end
