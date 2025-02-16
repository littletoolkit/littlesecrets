#!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh

# --
# Does a complete test of the cryptographic primitives for LittleSecrets.
# This tests the shell version.

SECRET="Hello, World!"
KEY="my-secret-key"

ls_store_init .
test-step "Encoding/Decoding transparency"
# Asserts the transparency of decoding
test-expect "$KEY" $(echo -n "$KEY" | ls_encode | ls_decode)

# Asserts the transparent of symmetric encoding
test-step "Symmetric Encryption transparency"
SECRET_ENC=$(echo -n "$SECRET" | ls_encrypt_sym "$KEY")
SECRET_DEC=$(echo -n "$SECRET_ENC" | ls_decrypt_sym "$KEY")
test-expect "$SECRET_DEC" "$SECRET"

test-step "Asymmetric Keypair"
test-expect "$(ls_key_id "$(ls_privkey_path)")" "private:pkcs8:valid=rsa" "Private key recognized"
test-expect "$(ls_key_id "$(ls_pubkey_path)")" "public:spki:" "Public key recognized"

test-step "Asymmetric Encryption transparency"
# NOTE: If you don't use ls_encode/ls_decode, then the contents will be mangled
SECRET_ENC=$(echo -n "$SECRET" | ls_encrypt_asym "$(ls_pubkey_path)" | ls_encode)
SECRET_DEC=$(echo -n "$SECRET_ENC" | ls_decode | ls_decrypt_asym "$(ls_privkey_path)")
test-expect "$SECRET_DEC" "$SECRET"

test-cleanup
# EOF
