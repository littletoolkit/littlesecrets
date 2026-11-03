#!/usr/bin/env bash
# Fault-injection overrides are invoked by the sourced helpers.
# shellcheck disable=SC1091,SC2329
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

export LITTLESECRETS_OPTIONS="hmac"
SECRET_VALUE="Legacy compatibility $(date)"

test-step "Init store"
ls_store_init || test-fail "Could not init store"

test-step "Create a secret"
SECRET_KEY="$(printf '%s' legacy-compatibility-key-material | ls_encode)"
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
rm -f .littlesecrets/secret/legacy.secret/secret.{sig,signer,format}

STORE="$(ls_store)"
OWNER="$(ls_user_name)@$(ls_user_host)"
cp -R "$STORE/secret/legacy.secret" legacy-v1

test-step "Prepare an unsigned v2 binary fixture"
printf 'v2\000binary\377\n\n' >binary-input
ls_secret_write legacy.v2 "" "$SECRET_KEY" v2 <binary-input >/dev/null
printf '%s' "$SECRET_KEY" | ls_encrypt_asym "$PUBKEY_PATH" >"$STORE/secret/legacy.v2/$OWNER.key"
rm "$STORE/secret/legacy.v2/secret."{sig,signer,format}
cp -R "$STORE/secret/legacy.v2" legacy-v2

test-step "Missing and invalid tags cannot initialize or migrate a legacy store"
rm "$STORE/store.id"
rm -rf "$LITTLESECRETS_TRUST_DIR"
mv "$STORE/secret/legacy.secret/secret.hmac" original-hmac
if ls_secret_get legacy.secret >rejected.out; then test-fail "Migrated a record without its HMAC"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/store.id"
printf '%064d' 0 >"$STORE/secret/legacy.secret/secret.hmac"
if ls_secret_get legacy.secret >rejected.out; then test-fail "Migrated a record with an invalid HMAC"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/store.id"
mv original-hmac "$STORE/secret/legacy.secret/secret.hmac"

test-step "First access automatically initializes trust and migrates v1"
test-expect "$(ls_secret_get legacy.secret)" "$SECRET_VALUE" "Legacy get succeeds without migration flags or setup"
test-exist "$STORE/store.id"
test-exist "$STORE/secret/legacy.secret/secret.sig"
test-expect "$(ls_secret_format_version legacy.secret)" v2 "Automatic migration writes v2"
cp -R "$STORE/secret/legacy.secret" migrated-record
test-expect-success ls_secret_verify legacy.secret
test-expect-success diff -r migrated-record "$STORE/secret/legacy.secret"

test-step "Automatic v2 migration preserves binary data"
"$BASE/src/sh/littlesecrets.sh" get legacy.v2 >binary-output
test-expect-success cmp binary-input binary-output
test-exist "$STORE/secret/legacy.v2/secret.sig"

test-step "Signed stores do not acquire trust automatically"
if env LITTLESECRETS_TRUST_DIR="$TEST_PATH/untrusted" "$BASE/src/sh/littlesecrets.sh" get legacy.v2 >rejected.out; then
	test-fail "Automatically trusted an existing signed store"
fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$TEST_PATH/untrusted"

test-step "Automatic initialization honors a custom store path"
mkdir -p custom-store/secret
cp -R legacy-v1 custom-store/secret/custom.secret
test-expect "$("$BASE/src/sh/littlesecrets.sh" -s "$TEST_PATH/custom-store" get custom.secret)" "$SECRET_VALUE"
test-exist custom-store/store.id
test-exist custom-store/secret/custom.secret/secret.sig

test-step "Every authenticated access path migrates legacy records"
for operation in ensure hash verify export upgrade; do
	cp -R legacy-v1 "$STORE/secret/via.$operation"
	ls_cli "$operation" "via.$operation" >"$operation.out" || test-fail "$operation did not migrate"
	test-exist "$STORE/secret/via.$operation/secret.sig"
done
cp -R legacy-v1 "$STORE/secret/via.key"
test-expect-success ls_secret_key via.key >/dev/null
test-exist "$STORE/secret/via.key/secret.sig"
cp -R legacy-v1 "$STORE/secret/via.compatibility"
test-expect "$("$BASE/src/sh/littlesecrets.sh" --allow-legacy get via.compatibility)" "$SECRET_VALUE"
test-exist "$STORE/secret/via.compatibility/secret.sig"
cp -R legacy-v1 "$STORE/secret/via.private.argument"
test-expect "$(ls_secret_get via.private.argument "$(cat "$(ls_privkey_path)")")" "$SECRET_VALUE"
test-exist "$STORE/secret/via.private.argument/secret.sig"

test-step "Missing recipient registrations stop migration without losing access"
ssh-keygen -q -t rsa -b 2048 -N '' -C bob@host -f "$TEST_PATH/bob"
mkdir -p "$STORE/user/bob"
ls_pubkey_import "$TEST_PATH/bob.pub" >"$STORE/user/bob/host.pubkey"
cp -R legacy-v1 "$STORE/secret/shared.legacy"
printf '%s' "$SECRET_KEY" | ls_encrypt_asym "$STORE/user/bob/host.pubkey" >"$STORE/secret/shared.legacy/bob@host.key"
cp -R "$STORE/secret/shared.legacy" shared-before
mv "$STORE/user/bob/host.pubkey" bob-registration
if ls_secret_get shared.legacy >rejected.out; then test-fail "Migrated without a recipient's public key"; fi
test-expect-failure test -s rejected.out
test-expect-success diff -r shared-before "$STORE/secret/shared.legacy"

test-step "Invalid checkout keys cannot replace the legacy record"
printf '%s' invalid-public-key >"$STORE/user/bob/host.pubkey"
if ls_secret_get shared.legacy >rejected.out; then test-fail "Migrated with an invalid public key"; fi
test-expect-failure test -s rejected.out
test-expect-success diff -r shared-before "$STORE/secret/shared.legacy"

test-step "Checkout registrations automatically preserve every recipient"
rm "$STORE/user/bob/host.pubkey"
ln -s "$TEST_PATH/bob-registration" "$STORE/user/bob/host.pubkey"
if ls_secret_get shared.legacy >rejected.out; then test-fail "Followed a symlinked recipient registration"; fi
test-expect-failure test -s rejected.out
test-expect-success diff -r shared-before "$STORE/secret/shared.legacy"
rm "$STORE/user/bob/host.pubkey"
mv bob-registration "$STORE/user/bob/host.pubkey"
test-expect "$(ls_secret_get shared.legacy)" "$SECRET_VALUE"
test-expect-success ls_trusted_pubkey "$STORE/user/bob/host.pubkey"
test-expect "$("$BASE/src/sh/littlesecrets.sh" -k "$TEST_PATH/bob" -u bob@host get shared.legacy)" "$SECRET_VALUE"

test-step "Grant and revoke migrate before changing recipients"
cp -R legacy-v1 "$STORE/secret/via.grant"
ls_secret_grant via.grant bob
test-expect "$("$BASE/src/sh/littlesecrets.sh" -k "$TEST_PATH/bob" -u bob@host get via.grant)" "$SECRET_VALUE"
cp -R shared-before "$STORE/secret/via.revoke"
ls_secret_revoke via.revoke bob
test-expect-failure test -e "$STORE/secret/via.revoke/bob@host.key"
test-expect "$(ls_secret_get via.revoke)" "$SECRET_VALUE"

test-step "Failed migration commits return no plaintext and restore the legacy record"
cp -R legacy-v1 "$STORE/secret/failed.migration"
if (
	mv() {
		case "$*" in *'.ls-stage.'*) return 1 ;; esac
		command mv "$@"
	}
	ls_secret_get failed.migration
) >rejected.out; then test-fail "Failed migration reported success"; fi
test-expect-failure test -s rejected.out
test-expect-success diff -r legacy-v1 "$STORE/secret/failed.migration"

test-step "Missing signed metadata cannot trigger a downgrade migration"
rm "$STORE/secret/legacy.secret/secret.sig"
if ls_secret_get legacy.secret >rejected.out; then test-fail "Re-signed a record with a missing signature"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/secret/legacy.secret/secret.sig"
rm "$STORE/secret/legacy.secret/secret."{format,signer}
if ls_secret_get legacy.secret >rejected.out; then test-fail "Accepted a signed envelope as a legacy master key"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/secret/legacy.secret/secret.sig"

test-step "Concurrent reads migrate one complete record"
cp -R legacy-v1 "$STORE/secret/concurrent.legacy"
pids=()
for reader in one two three; do
	("$BASE/src/sh/littlesecrets.sh" get concurrent.legacy >"reader-$reader.out") &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || test-fail "Concurrent legacy reader failed"; done
for reader in one two three; do test-expect "$(cat "reader-$reader.out")" "$SECRET_VALUE"; done
test-expect-success ls_secret_verify concurrent.legacy

test-end
