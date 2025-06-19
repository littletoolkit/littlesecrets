#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/tests/lib-testing.sh"
source "$BASE/src/sh/littlesecrets.sh"

# --
# Does a complete test of the cryptographic primitives for LittleSecrets.
# This tests the shell version.

SECRET="Hello, World!"
KEY="my-secret-key"

test-start
ls_store_init .

# Asserts the transparency of decoding
test-step "Encoding/Decoding transparency"
test-expect "$KEY" $(echo -n "$KEY" | ls_encode | ls_decode)

# Asserts the transparent of symmetric encoding
test-step "Symmetric Encryption transparency"
SECRET_ENC=$(echo -n "$SECRET" | test-expect-success ls_encrypt_sym "$KEY")
SECRET_DEC=$(echo -n "$SECRET_ENC" | test-expect-success ls_decrypt_sym "$KEY")
test-expect "$SECRET_DEC" "$SECRET"

test-step "Asymmetric Keypair"
test-expect "$(ls_key_id "$(ls_privkey_path)")" "private:rsa+pem+pkcs8:valid=rsa" "Private key recognized"
test-expect "$(ls_key_id "$(ls_pubkey_path)")" "public:spki:" "Public key recognized"

# NOTE: If you don't use ls_encode/ls_decode, then the contents will be mangled
test-step "Asymmetric Encryption transparency"
SECRET_ENC=$(echo -n "$SECRET" | ls_encrypt_asym "$(ls_pubkey_path)" | ls_encode)
SECRET_DEC=$(echo -n "$SECRET_ENC" | ls_decode | ls_decrypt_asym "$(ls_privkey_path)")
test-expect "$SECRET_DEC" "$SECRET"
echo "$SECRET_DEC" "$SECRET"

test-end

# EOF
