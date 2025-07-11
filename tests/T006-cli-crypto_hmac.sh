#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/tests/lib-testing.sh"
source "$BASE/src/sh/littlesecrets.sh"

# We pretend this is an encrypted secret
# and key
SECRET_ENC="Hello, World!"
SECRET_KEY="my-secret-key"

test-start

test-step "HMAC Encoding"
HMAC=$(echo -n "$SECRET_ENC" | ls_hmac "$SECRET_KEY")
test-noempty "$HMAC" "HMAC command returns non-empty value"
test_log_output "HMAC=$HMAC"

test-step "HMAC Encoding Stability"
HMAC_2=$(echo -n "$SECRET_ENC" | ls_hmac "$SECRET_KEY")
test_log_output "HMAC=$HMAC_2"
test-expect "$HMAC" "$HMAC_2" "HMAC returns the same output when called twice"

# NOTE: the `ls_secret_hmac_key` function does ensure the key is HMAC-able
test-step "Secret Key to HMAC key"
SECRET_HMAC_KEY="$(ls_secret_hmac_key "$SECRET_KEY")"
test-expect-different "$SECRET_KEY" "$SECRET_HMAC_KEY"

test-step "ls_secret_hmac transparency"
HMAC_0=$(echo -n "$SECRET_ENC" | ls_hmac "$SECRET_HMAC_KEY")
HMAC_3=$(echo -n "$SECRET_ENC" | ls_secret_hmac "-" "$SECRET_KEY")
test_log_output "HMAC=$HMAC_3"
test-expect "$HMAC_0" "$HMAC_3" "ls_secret_hmac returns the same as ls_hmac"
# EOF
