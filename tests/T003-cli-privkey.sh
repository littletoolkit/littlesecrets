#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2119
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/tests/lib-testing.sh
source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"/src/sh/littlesecrets.sh

# --
# Tests the generation of a new private key, and teh encryption/decryption
# using that key.

test-start

ls_store_init .

test-step "Generation of a new private key"
SECRET="Hello, World $(date)!"
PRIVKEY=$(ls_privkey_new)
PUBKEY=$(ls_pubkey_import "$PRIVKEY")

test-step "Derivation of public key from private key"
test-expect "$(echo "$PRIVKEY" | ls_key_format)" "private:pkcs8:valid=rsa" "Private key is valid"
test-expect "$(ls_user_pubkey "" "$PRIVKEY" | ls_key_format)" "public:spki:" "Public key is derived"

ENCKEY="HELLO_WORLD_ENC"

test-step "Add secret with new public key"

if test-expect-success ls_secret_add hello.world "$SECRET" "$PUBKEY" "$ENCKEY"; then
	test_log_success "Secret hello.world added"
fi

test-exist "$(ls_secret_key_path hello.world)" "Secret key path exists"
test-exist "$(ls_secret_path hello.world)" "Encrypted secret path exists"

test-step "Testing secret encryption key asymmetric decryption"
test-expect "$(ls_secret_key hello.world "$PRIVKEY")" "$ENCKEY" "Encryption key is as expected"
test-expect "$(ls_decrypt_asym "$PRIVKEY" "$(ls_secret_key_path hello.world)")" "$ENCKEY" "Enc key asym decryption works"

test-step "Testing full secret decryption"
test-expect "$(ls_secret_get hello.world "$PRIVKEY")" "$SECRET" "Full decryption works"

# EOF
