#!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh

# --
# Does a complete test of the cryptographic primitives for LittleSecrets.
# This tests the shell version.

SECRET="Hello, World!"
KEY="my-secret-key"

test-step "Encoding/Decoding transparency"
# Asserts the transparency of decoding
test-expect "$KEY" $(echo -n "$KEY" | ls_encode | ls_decode)

# Asserts the transparent of symmetric encoding
test-step "Symmetric Encryption transparency"
SECRET_ENC=$(ls_encrypt_sym "$(echo -n "$SECRET" | ls_encode)" "$KEY")
test-expect "$(ls_decrypt_sym "$SECRET_ENC" "$KEY")" "$SECRET"

test-step "Asymmetric Keypair"
test-expect "$(ls_keyid "$(ls_privkey)")" "private:pkcs8+rsa:valid"
test-expect "$(ls_pubkey | ls_keyid)" "public:spki"

test-step "Asymmetric Encryption transparency"
SECRET_ENC=$(ls_encrypt_asym "$(echo -n "$SECRET" | ls_encode)")
test-expect "$(ls_decrypt_asym "$SECRET_ENC")" "$SECRET"

test-cleanup
# EOF
