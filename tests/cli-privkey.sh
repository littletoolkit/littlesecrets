#!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh

# --
# Tests the generation of a new private key, and teh encryption/decryption
# using that key.

test-start

ls_store_init .

test-step "Generation of a new private key"
SECRET="Hello, World $(date)!"
PRIVKEY=$(ls_privkey_new)
test-info "Derivation of public key from private key"
test-expect "$(echo "$PRIVKEY" | ls_key_id)" "private:pkcs8:valid=rsa" "Private key is valid"
test-expect "$(ls_user_pubkey "" "$PRIVKEY" | ls_key_id)" "public:spki:" "Public key is derived"

ENCKEY="HELLO_WORLD_ENC"
test-step "Add secret with new private key"
ls_secret_add hello.world "$SECRET" "$PRIVKEY" "$ENCKEY"
test-exist "$(ls_secret_key_path hello.world)" # Secret key path exists
test-exist "$(ls_secret_path hello.world)"     # Encrypted secret path exists

test-step "Testing secret encryption key asymmetric decryption"
test-expect "$(ls_secret_key hello.world "$PRIVKEY")" "$ENCKEY" "Encryption key is as expected"
test-expect "$(ls_decrypt_asym "$PRIVKEY" "$(ls_secret_key_path hello.world)")" "$ENCKEY" "Enc key asym decryption works"
test-step "Testing full secret decryption"
test-expect "$(ls_secret_get hello.world "$PRIVKEY")" "$SECRET"

test-cleanup

# EOF
