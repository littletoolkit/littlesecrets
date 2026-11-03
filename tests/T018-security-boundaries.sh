#!/usr/bin/env bash
# Fault-injection overrides are called indirectly by the sourced helpers.
# shellcheck disable=SC1091,SC2329
set -euo pipefail
shopt -s extglob
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"
test-start

ls_store_init >/dev/null
ssh-keygen -q -t rsa -b 2048 -N '' -C bob@host -f "$TEST_PATH/bob"
ls_user_register bob@host "$TEST_PATH/bob.pub" >/dev/null
ls_secret_add alpha 'original alpha' >/dev/null
ls_secret_add beta 'private beta' >/dev/null
STORE="$TEST_PATH/.littlesecrets"
OWNER="$(ls_user_name)@$(ls_user_host)"
cp -R "$STORE/secret/alpha" "$TEST_PATH/original"

restore_alpha() {
	rm -rf "$STORE/secret/alpha"
	cp -R "$TEST_PATH/original" "$STORE/secret/alpha"
}

test-step "Deleting a tag cannot authorize modified ciphertext"
printf '\001' | dd of="$STORE/secret/alpha/secret.enc" bs=1 seek=32 conv=notrunc 2>/dev/null
rm "$STORE/secret/alpha/secret.hmac"
if ls_secret_get alpha >rejected.out; then test-fail "Accepted unauthenticated ciphertext"; fi
test-expect-failure test -s rejected.out
test-expect-failure ls_cli verify alpha
if ls_secret_export alpha >rejected.out; then test-fail "Export succeeded without authentication"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/secret/alpha/secret.hmac"
restore_alpha

test-step "Ensure cannot replace a damaged record"
rm "$STORE/secret/alpha/secret.enc"
if ls_secret_ensure alpha >rejected.out; then test-fail "Ensure replaced damaged ciphertext"; fi
test-expect-failure test -s rejected.out
test-expect-failure test -e "$STORE/secret/alpha/secret.enc"
restore_alpha

test-step "Recipient-envelope and whole-record substitution cannot redirect grants"
cp "$STORE/secret/beta/$OWNER.key" "$STORE/secret/alpha/$OWNER.key"
test-expect-failure ls_secret_grant alpha bob
test-expect-failure test -e "$STORE/secret/alpha/bob@host.key"
rm -rf "$STORE/secret/alpha"
cp -R "$STORE/secret/beta" "$STORE/secret/alpha"
test-expect-failure ls_secret_get alpha
test-expect-failure ls_secret_grant alpha bob
restore_alpha

test-step "Unpinned host keys cannot capture writes; changed recipient keys cannot capture grants"
cp "$STORE/user/bob/host.pubkey" "$STORE/user/$(ls_user_name)/injected.pubkey"
test-expect-failure ls_secret_add alpha replacement
test-expect-success diff -r "$TEST_PATH/original" "$STORE/secret/alpha"
rm "$STORE/user/$(ls_user_name)/injected.pubkey"
cp "$STORE/user/bob/host.pubkey" bob-pinned.pubkey
cp "$STORE/user/$(ls_user_name)/$(ls_user_host).pubkey" "$STORE/user/bob/host.pubkey"
test-expect-failure ls_secret_grant alpha bob
cp bob-pinned.pubkey "$STORE/user/bob/host.pubkey"

test-step "Store and destination symlinks cannot modify external files"
printf '%s' untouched >outside
ln -s "$TEST_PATH/outside" destination
tmp="$(ls_mkstemp)"
printf '%s' replacement >"$tmp"
test-expect-failure ls_try_write "$tmp" "$TEST_PATH/destination" true
test-expect "$(cat outside)" untouched
mkdir external
printf '%s' untouched >"external/$(ls_user_host).pubkey"
mv "$STORE/user/$(ls_user_name)" saved-user
ln -s "$TEST_PATH/external" "$STORE/user/$(ls_user_name)"
test-expect-failure ls_user_deregister "$(ls_user_name)"
test-expect-failure ls_user_register
test-expect "$(cat "external/$(ls_user_host).pubkey")" untouched
rm "$STORE/user/$(ls_user_name)"
mv saved-user "$STORE/user/$(ls_user_name)"
mv "$STORE/secret" saved-secrets
ln -s "$TEST_PATH/external" "$STORE/secret"
test-expect-failure ls_secret_add alpha replacement
test-expect-failure ls_secret_remove alpha
rm "$STORE/secret"
mv saved-secrets "$STORE/secret"
test-expect-failure test -e external/alpha

test-step "A symlink to the store works without relaxing internal checks"
ln -s "$STORE" linked-store
if ( LITTLESECRETS_STORE="$TEST_PATH/linked-store"; test-expect "$(ls_secret_get alpha)" 'original alpha' ); then
	test-ok "Symlinked store resolves to the trusted store"
else
	test-fail "Symlinked store could not be read"
fi

test-step "Crypto failures fail closed and preserve the previous generation"
if (
	ls_hmac() { return 1; }
	if ls_secret_hmac_v2 /dev/null key >failed-tag; then exit 1; fi
	[ ! -s failed-tag ] || exit 1
	if ls_secret_add alpha replacement; then exit 1; fi
	if ls_secret_get alpha >failed-plaintext; then exit 1; fi
	[ ! -s failed-plaintext ]
); then test-ok "No tag, plaintext, or update is accepted after MAC failure"; else test-fail "MAC failure was ignored"; fi
test-expect-success diff -r "$TEST_PATH/original" "$STORE/secret/alpha"
printf '%s' invalid-public-key >bad.pub
test-expect-failure ls_secret_add alpha replacement "$TEST_PATH/bad.pub"
test-expect-success diff -r "$TEST_PATH/original" "$STORE/secret/alpha"

test-step "A failed commit restores the previous record and releases its lock"
if (
	mv() {
		case "$*" in *'.ls-stage.'*) return 1 ;; esac
		command mv "$@"
	}
	ls_secret_add alpha replacement
); then test-fail "Failed rename reported success"; fi
test-expect-success diff -r "$TEST_PATH/original" "$STORE/secret/alpha"
test-expect "$(ls_secret_get alpha)" 'original alpha'
test-expect-failure test -e "$STORE/secret/.alpha.lock.d"

test-step "A failed file copy does not truncate the destination"
tmp="$(ls_mkstemp)"
printf '%s' replacement >"$tmp"
if (cat() { return 1; }; ls_try_write "$tmp" "$TEST_PATH/outside" true); then
	test-fail "Failed copy reported success"
fi
test-expect "$(cat outside)" untouched

test-step "Verification fails when the current user has no recipient key"
test-expect-failure env LITTLESECRETS_USER=bob@host LITTLESECRETS_KEY="$TEST_PATH/bob" "$BASE/src/sh/littlesecrets.sh" verify alpha

test-step "Invalid private-key arguments do not disclose their contents"
invalid_key=$'-----BEGIN PRIVATE KEY-----\nsynthetic-private-material\n-----END PRIVATE KEY-----'
if env LITTLESECRETS_KEY="$invalid_key" "$BASE/src/sh/littlesecrets.sh" get alpha >rejected.out 2>key-error; then
	test-fail "Accepted a key value where a path is required"
fi
test-expect-failure grep -q synthetic-private-material key-error
test-expect-failure test -s rejected.out

test-step "Export remains literal with xpg_echo and preserves trailing newlines"
payload='\\047; touch export-injected; #'
printf '%s\n\n' "$payload" >text-input
ls_secret_add literal <text-input >/dev/null
if (
	shopt -s xpg_echo
	assignments="$(ls_secret_export EXPORTED=literal)" || exit 1
	eval "$assignments"
	printf '%s' "$EXPORTED" | cmp -s - text-input
) && [ ! -e export-injected ]; then test-ok "Export is literal and byte preserving"; else test-fail "Export altered or executed the value"; fi

test-step "Binary secrets survive API, CLI, and JSON round trips"
printf '\000hello\377\n\n' >binary-input
ls_secret_add binary <binary-input >/dev/null
ls_secret_get binary >binary-output
test-expect-success cmp binary-input binary-output
"$BASE/src/sh/littlesecrets.sh" get binary >binary-output
test-expect-success cmp binary-input binary-output
"$BASE/src/sh/littlesecrets.sh" -f json get binary |
	awk -F '"' '/"value":/ {printf "%s", $4}' |
	"$LITTLESECRETS_OPENSSL_BIN" base64 -d -A >binary-output
test-expect-success cmp binary-input binary-output
if ls_secret_export binary >rejected.out; then test-fail "Shell export silently lost NUL bytes"; fi
test-expect-failure test -s rejected.out

test-step "Forced JSON text rejects invalid UTF-8 without partial output"
if "$BASE/src/sh/littlesecrets.sh" -f json --text get binary >rejected.out; then
	test-fail "Forced text emitted invalid UTF-8"
fi
test-expect-failure test -s rejected.out

test-step "Revocation works after deregistration and rotates the master key"
ls_secret_grant alpha bob
old_key="$(ls_secret_key alpha)"
ls_user_deregister bob
ls_secret_revoke alpha bob
test-expect-failure test -e "$STORE/secret/alpha/bob@host.key"
test-expect-different "$(ls_secret_key alpha)" "$old_key" "Revocation rotates the master key"
test-expect "$(ls_secret_get alpha)" 'original alpha'

test-step "Decryption uses the authenticated snapshot if the store changes afterward"
cp -R "$STORE/secret/alpha" snapshot-original
if (
	eval "$(declare -f ls_record_open | sed '1s/ls_record_open/ls_test_record_open/')"
	ls_record_open() {
		ls_test_record_open "$@" || return 1
		printf '%s' changed-after-verification >"$STORE/secret/$1/secret.enc"
	}
	[ "$(ls_secret_get alpha)" = 'original alpha' ]
); then test-ok "Verified bytes, rather than the reopened store, are decrypted"; else test-fail "Decryption reopened mutable ciphertext"; fi
rm -rf "$STORE/secret/alpha"
mv snapshot-original "$STORE/secret/alpha"

test-step "Command-substitution temporaries are removed on normal exit and SIGTERM"
for termination in normal signal; do
	if bash -s -- "$BASE/src/sh/littlesecrets.sh" "$TEST_PATH/temporary-paths" "$termination" <<'CHILD'
source "$1"
tmp="$(ls_mkstemp)"
printf '%s' synthetic-secret >"$tmp"
printf '%s\n%s\n' "$LS_TEMP_DIR" "$tmp" >"$2"
if [ "$3" = signal ]; then kill -TERM "$BASHPID"; fi
CHILD
	then [ "$termination" = normal ] || test-fail "SIGTERM did not terminate the process"; fi
	while IFS= read -r path; do test-expect-failure test -e "$path"; done <temporary-paths
done

test-step "Concurrent writers publish complete authenticated records"
pids=()
for value in one two three; do
	("$BASE/src/sh/littlesecrets.sh" set alpha "$value") &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || test-fail "Concurrent writer failed"; done
test-expect-success ls_secret_verify alpha

test-step "Concurrent initializers agree on one pinned store identity"
mkdir concurrent-init
pids=()
for value in one two three; do
	(ls_store_init "$TEST_PATH/concurrent-init" >"init-$value") &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || test-fail "Concurrent initializer failed"; done
test-expect-success ls_store_trust "$TEST_PATH/concurrent-init/.littlesecrets"

test-step "A changed store identity never replaces its local pin"
cp "$STORE/store.id" original-id
printf '%032d\n' 0 >"$STORE/store.id"
test-expect-failure ls_store_init
test-expect-failure ls_secret_get alpha
mv original-id "$STORE/store.id"
test-expect-success ls_secret_verify alpha

test-step "Concurrent ensure calls return the same value"
pids=()
for value in one two three; do
	("$BASE/src/sh/littlesecrets.sh" ensure concurrent >"ensure-$value") &
	pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || test-fail "Concurrent ensure failed"; done
test-expect-success cmp ensure-one ensure-two
test-expect-success cmp ensure-one ensure-three

test-end
