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
test-expect "$KEY" $(echo -n "$KEY" | ls_encode | ls_decode) "Value decoded"

# Asserts the transparent of symmetric encoding
test-step "Symmetric Encryption transparency"
KEY_ENC=$(echo -n "$KEY" | ls_encode)
SECRET_ENC=$(echo -n "$SECRET" | test-expect-success ls_encrypt_sym "$KEY_ENC")
SECRET_DEC=$(echo -n "$SECRET_ENC" | test-expect-success ls_decrypt_sym "$KEY_ENC")
test-expect "$SECRET_DEC" "$SECRET" "Secret symmetrically decoded"

test-step "Asymmetric Keypair"
test-expect "$(ls_key_id "$(ls_privkey_path)")" "private:pkcs8:valid=rsa" "Private key recognized"
test-expect "$(ls_key_id "$(ls_pubkey_path)")" "public:spki:" "Public key recognized"

# NOTE: If you don't use ls_encode/ls_decode, then the contents will be mangled
test-step "Asymmetric Encryption transparency"
SECRET_ENC=$(echo -n "$SECRET" | ls_encrypt_asym "$(ls_pubkey_path)" | ls_encode)
SECRET_DEC=$(echo -n "$SECRET_ENC" | ls_decode | ls_decrypt_asym "$(ls_privkey_path)")
test-expect "$SECRET_DEC" "$SECRET" "Secret asymmetrically decoded"

test-step "HMAC Validation"
test-expect-different "$(echo -n "$SECRET" | ls_secret_hmac - "$KEY")" "$(echo -n "${SECRET}X" | ls_secret_hmac - "$KEY")" "HMAC signature changes based on secret"

test-end

# EOF
