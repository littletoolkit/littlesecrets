#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Init store and check directory permissions"
ls_store_init || test-fail "Could not init store"
STORE_PERMS=$(stat -c "%a" .littlesecrets 2>/dev/null || stat -f "%Lp" .littlesecrets)
test-expect "$STORE_PERMS" "700" "Store directory has 700 permissions"

test-step "SEC-01: Safe export quoting and command injection prevention"
MALICIOUS_VAL="value'; touch injected.txt; echo '"
echo -n "$MALICIOUS_VAL" | ls_secret_add test.injection || test-fail "Could not add secret"
EXPORT_OUT="$(ls_cli export TEST_VAR=test.injection)"
eval "$EXPORT_OUT"
# Verify injected.txt was NOT created
if [ -e "injected.txt" ]; then
	rm -f "injected.txt"
	test-fail "Command injection succeeded in export"
else
	test-ok "No command injection executed via export eval"
fi
test-expect "$TEST_VAR" "$MALICIOUS_VAL" "Exported value matches original exactly after eval"

test-step "SEC-01: Rejection of invalid environment variable names in export"
test-expect-failure ls_cli export "INVALID-NAME=test.injection"
test-expect-failure ls_cli export "MALICIOUS\$(id)=test.injection"

test-step "SEC-02: Path traversal rejection in secret remove"
test-expect-failure ls_cli remove "../../secret"
test-expect-failure ls_cli remove "../.."
test-expect-failure ls_cli remove "/"

test-step "SEC-04: Path traversal rejection in secret and user names"
test-expect-failure ls_cli add "../../escaped" "bad"
test-expect-failure ls_cli get "../../escaped"
test-expect-failure ls_cli register "../../baduser@badhost"

test-step "SEC-03: Symmetric encryption handles binary keys with newlines"
BIN_KEY=$'my\nkey\nwith\nnewlines\n'
BIN_KEY_ENC=$(printf '%s' "$BIN_KEY" | ls_encode)
MSG="Sensitive payload to encrypt"
DEC=$(printf '%s' "$MSG" | ls_encrypt_sym "$BIN_KEY_ENC" | ls_decrypt_sym "$BIN_KEY_ENC")
test-expect "$DEC" "$MSG" "Binary key with newlines correctly encrypts and decrypts"

test-step "SEC-06 & SEC-11: HMAC verification prevents tampered secret decryption"
echo -n "original text" | ls_secret_add tamper.test || test-fail "Could not add secret"
test-expect "$(ls_secret_get tamper.test)" "original text" "Secret retrieves before tampering"
# Tamper with the ciphertext directly
echo "corrupted-ciphertext" > .littlesecrets/secret/tamper.test/secret.enc
test-expect-failure ls_secret_get tamper.test
test-expect-failure ls_cli get tamper.test

test-step "SEC-10: File permissions on secret files"
echo -n "secret-perms" | ls_secret_add perms.test || test-fail "Could not add secret"
ENC_PERMS=$(stat -c "%a" .littlesecrets/secret/perms.test/secret.enc 2>/dev/null || stat -f "%Lp" .littlesecrets/secret/perms.test/secret.enc)
test-expect "$ENC_PERMS" "600" "Secret ciphertext file has 600 permissions"

test-step "SEC-14: Raw key data is not stat-ed as a file path"
RAW_PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD dummy@host"
test-expect-failure ls_is_path "$RAW_PUBKEY"
RAW_PEM="-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A\n-----END PUBLIC KEY-----"
test-expect-failure ls_is_path "$RAW_PEM"

test-step "SEC-15: Binary detection correctly distinguishes UTF-8 from binary"
TMP_UTF8=$(ls_mkstemp)
printf "Café, naïve, façade, 🚀, 中文\n" > "$TMP_UTF8"
if ls_is_binary_file "$TMP_UTF8"; then
	test-fail "UTF-8 text falsely identified as binary"
else
	test-ok "UTF-8 text correctly identified as text"
fi
TMP_BIN=$(ls_mkstemp)
printf "Hello\x00World" > "$TMP_BIN"
if ls_is_binary_file "$TMP_BIN"; then
	test-ok "Binary with null byte correctly identified as binary"
else
	test-fail "Binary file not detected as binary"
fi

test-end
