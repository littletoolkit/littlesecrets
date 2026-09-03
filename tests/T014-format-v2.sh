#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Init store"
ls_store_init || test-fail "Could not init store"

test-step "Add secret using default v2 format"
MSG_V2="Hello from Format v2 (Encrypt-then-MAC)!"
echo -n "$MSG_V2" | ls_cli add secret.v2 || test-fail "Could not add v2 secret"

test-step "Verify v2 format identification"
test-exist .littlesecrets/secret/secret.v2/secret.hmac
HMAC_CONTENT="$(cat .littlesecrets/secret/secret.v2/secret.hmac)"
test-substring "$HMAC_CONTENT" "v2:etm:"
test-expect "$(ls_secret_format_version secret.v2)" "v2" "Format version identified as v2"

test-step "Retrieve v2 secret"
RETRIEVED_V2="$(ls_cli get secret.v2)"
test-expect "$RETRIEVED_V2" "$MSG_V2" "Retrieved v2 secret matches plaintext exactly"

test-step "v2 Verify succeeds on untampered secret"
test-expect-success ls_cli verify secret.v2

test-step "v2 Encrypt-then-MAC: reject tampered ciphertext immediately"
echo "tampered-ciphertext-bits" > .littlesecrets/secret/secret.v2/secret.enc
test-expect-failure ls_cli get secret.v2
test-expect-failure ls_cli verify secret.v2

test-step "Add legacy v1 secret with --v1 flag"
MSG_V1="Hello from Format v1 (Legacy)!"
echo -n "$MSG_V1" | ls_cli --v1 add secret.v1 || test-fail "Could not add v1 secret"

test-step "Verify v1 format identification"
test-exist .littlesecrets/secret/secret.v1/secret.hmac
HMAC_V1_CONTENT="$(cat .littlesecrets/secret/secret.v1/secret.hmac)"
test-expect-different "${HMAC_V1_CONTENT:0:7}" "v2:etm:" "v1 HMAC has no v2 prefix"
test-expect "$(ls_secret_format_version secret.v1)" "v1" "Format version identified as v1"

test-step "Retrieve v1 secret (backward compatibility)"
RETRIEVED_V1="$(ls_cli get secret.v1)"
test-expect "$RETRIEVED_V1" "$MSG_V1" "Retrieved v1 secret matches plaintext exactly"

test-step "Mixed repository export"
EXPORT_OUT="$(ls_cli export)"
test-substring "$EXPORT_OUT" "SECRET_V1"
test-substring "$EXPORT_OUT" "SECRET_V2"

test-end
