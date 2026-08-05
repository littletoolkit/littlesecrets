#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

# --
# Tests ensure command

test-start

test-step "Init store"
ls_store_init || test-fail "Could not init store"

test-step "Ensure non-existent secret creates new secret"
# First ensure should create a new secret
ls_cli ensure test.secret || test-fail "Could not ensure new secret"
test-exist .littlesecrets/secret/test.secret/secret.enc

# Verify the secret was created and is 16 characters
SECRET_VALUE=$(ls_secret_get test.secret)
if [ ${#SECRET_VALUE} -ne 16 ]; then
    test-fail "Generated secret should be 16 characters, got ${#SECRET_VALUE}"
fi

# Verify the secret contains only printable ASCII characters (32-126)
if ! echo "$SECRET_VALUE" | od -An -t u1 | tr -s ' ' '\n' | grep -q '^[3-9][2-9]\|1[0-1][0-9]\|12[0-6]$'; then
    test-fail "Generated secret contains non-printable characters: $SECRET_VALUE"
fi

test-step "Ensure existing secret with access returns success"
# Second ensure should succeed since we have access
ls_cli ensure test.secret || test-fail "Could not ensure existing secret with access"

# Value should remain the same
NEW_SECRET_VALUE=$(ls_secret_get test.secret)
test-expect "$NEW_SECRET_VALUE" "$SECRET_VALUE" "Secret value should not change on second ensure"

test-step "Test ensure fails when user doesn't have access"
# Create a new private key that won't have access
PRIVKEY=$(test-expect-success ls_privkey_new)

# Try to ensure the existing secret with the new key - should fail
test-expect-failure ls_cli -k "$PRIVKEY" ensure test.secret

# EOF
