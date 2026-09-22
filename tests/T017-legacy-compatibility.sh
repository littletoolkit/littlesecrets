#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

export LITTLESECRETS_OPTIONS="hmac"
SECRET_VALUE="Legacy compatibility $(date)"

test-step "Init store"
ls_store_init || test-fail "Could not init store"

test-step "Create a secret"
SECRET_KEY="$(ls_key)"
printf '%s' "$SECRET_VALUE" | ls_secret_write legacy.secret "" "$SECRET_KEY" "v1" >/dev/null || test-fail "Could not create secret"

test-step "Rewrite recipient key with legacy RSA padding"
PUBKEY_PATH="$(ls_pubkey_path)"
SECRET_KEY_PATH="$(ls_secret_key_path legacy.secret)"
LEGACY_KEY_PATH="$(ls_mkstemp)"
printf '%s' "$SECRET_KEY" | "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -encrypt -pubin -inkey "$PUBKEY_PATH" -out "$LEGACY_KEY_PATH" -pkeyopt rsa_padding_mode:pkcs1 || test-fail "Could not create legacy recipient key"
cat "$LEGACY_KEY_PATH" >"$SECRET_KEY_PATH"

test-step "Rewrite ciphertext with legacy passphrase handling"
LEGACY_PASS_PATH="$(ls_mkstemp)"
LEGACY_SECRET_PATH="$(ls_mkstemp)"
printf '%s' "$SECRET_KEY" | ls_decode >"$LEGACY_PASS_PATH"
exec 3<"$LEGACY_PASS_PATH"
printf '%s' "$SECRET_VALUE" | "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -out "$LEGACY_SECRET_PATH" -pass fd:3 || test-fail "Could not create legacy ciphertext"
exec 3<&-
cat "$LEGACY_SECRET_PATH" >"$(ls_secret_path legacy.secret)/secret.enc"
rm -f "$(ls_secret_hmac_path legacy.secret)"

test-step "Read legacy secret with HMAC disabled"
test-expect "$(unset LITTLESECRETS_OPTIONS; ls_secret_get legacy.secret)" "$SECRET_VALUE" "Legacy secret read transparently"
test-empty "$(ls_secret_hmac_path legacy.secret)" "HMAC not created when hmac option is disabled"

test-step "Verify and recover legacy secret"
ls_secret_verify legacy.secret || test-fail "Could not verify legacy secret"
test-exist .littlesecrets/secret/legacy.secret/secret.hmac
test-expect "$(ls_secret_get legacy.secret)" "$SECRET_VALUE" "Legacy secret recovered"
test-expect "$(ls_secret_format_version legacy.secret)" "v1" "Recovered legacy HMAC stays v1"
test-expect-different "$(cat .littlesecrets/secret/legacy.secret/secret.hmac | cut -c1-7)" "v2:etm:" "Recovered legacy HMAC is not v2-prefixed"

# EOF
