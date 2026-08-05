#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

# Enable HMAC option
export LITTLESECRETS_OPTIONS="hmac"

SECRET1="Hello, World $(date)!"
SECRET2="Updated secret $(date)!"

test-step "Init store"
ls_store_init || test-fail "Could not init store"

test-step "Add secret with HMAC option enabled"
echo -n "$SECRET1" | ls_secret_add test.secret || test-fail "Could not add secret"

test-step "Verify secret files exist"
test-exist .littlesecrets/secret/test.secret/secret.enc
test-exist .littlesecrets/secret/test.secret/"$USER"@"$HOSTNAME".key

test-step "Verify HMAC file is created"
test-exist .littlesecrets/secret/test.secret/secret.hmac
HMAC1=$(cat .littlesecrets/secret/test.secret/secret.hmac)
test-noempty "$HMAC1" "HMAC file contains data"

test-step "Verify HMAC is valid"
EXPECTED_HMAC1=$(ls_secret_hmac test.secret)
test-expect "$HMAC1" "$EXPECTED_HMAC1" "HMAC matches expected value"

test-step "Update secret with new content"
echo -n "$SECRET2" | ls_secret_write test.secret || test-fail "Could not update secret"

test-step "Verify secret content is updated"
test-expect "$(ls_secret_get test.secret)" "$SECRET2" "Secret content updated"

test-step "Verify HMAC is updated"
HMAC2=$(cat .littlesecrets/secret/test.secret/secret.hmac)
test-noempty "$HMAC2" "Updated HMAC file contains data"
test-expect-different "$HMAC1" "$HMAC2" "HMAC changed after secret update"

test-step "Verify updated HMAC is valid"
EXPECTED_HMAC2=$(ls_secret_hmac test.secret)
test-expect "$HMAC2" "$EXPECTED_HMAC2" "Updated HMAC matches expected value"

test-step "Test secret creation without HMAC option"
export LITTLESECRETS_OPTIONS=""
echo -n "$SECRET1" | ls_secret_add test.secret.no.hmac || test-fail "Could not add secret without HMAC"

test-step "Verify no HMAC file is created without option"
if [ -e .littlesecrets/secret/test.secret.no.hmac/secret.hmac ]; then
	test-fail "HMAC file should not exist without option"
else
	test-ok "No HMAC file created without option"
fi

test-step "Re-enable HMAC and update existing secret"
export LITTLESECRETS_OPTIONS="hmac"
echo -n "$SECRET1" | ls_secret_write test.secret.no.hmac || test-fail "Could not update secret"

test-step "Verify HMAC is created when option is enabled"
test-exist .littlesecrets/secret/test.secret.no.hmac/secret.hmac
HMAC3=$(cat .littlesecrets/secret/test.secret.no.hmac/secret.hmac)
test-noempty "$HMAC3" "HMAC file created when option enabled"

test-step "Verify newly created HMAC is valid"
EXPECTED_HMAC3=$(ls_secret_hmac test.secret.no.hmac)
test-expect "$HMAC3" "$EXPECTED_HMAC3" "Newly created HMAC matches expected value"

# EOF
