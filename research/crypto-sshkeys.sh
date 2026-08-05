#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091

source "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/tests/lib-testing.sh"

# --
# Tests the creation of an SSH keypair, and the derivation of a PEM keypair
# from the SSH private key.
# 
# Note that it is possible to generate the PEM keypair directly which OpenSSL
# but it defeats the prurpose a bit.

test-start

KEYSPATH=$(mktemp -d -t littlesecrets.XXX.keys)
PRIVATE_KEY_PATH=$KEYSPATH/keypair.priv           # BEGIN OPENSSH PRIVATE KEY
PRIVATE_KEY_PEM_PATH="$PRIVATE_KEY_PATH".pem      # BEGIN RSA PRIVATE KEY
PUBLIC_KEY_PATH=$KEYSPATH/keypair.priv.pub        # ssh-rsa XXXX
PUBLIC_KEY_PKCS8_PATH="$PUBLIC_KEY_PATH".pem      # BEGIN PUBLIC KEY
TEST_CLEAN+=("$PRIVATE_KEY_PATH" "$PRIVATE_KEY_PEM_PATH" "$PUBLIC_KEY_PATH" "$PUBLIC_KEY_PKCS8_PATH")

# NOTE: The following creates an RSA PEM keypair directly
# test-run "openssl genrsa -out ""$PRIVATE_KEY_PATH"" 2048"
# test-log "Writing private PEM key: $PRIVATE_KEY_PEM_PATH "
# test-run "openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in ""$PRIVATE_KEY_PATH"" -out ""$PRIVATE_KEY_PEM_PATH"
# test-log "Converting RSA private key to RSA public key: $PUBLIC_KEY_PATH"
# test-run "openssl rsa -in ""$PRIVATE_KEY_PATH"" -pubout -out ""$PUBLIC_KEY_PATH"" 2> /dev/null"

# This is for using SSH, as we want
test-log "Writing private SSH/RSA key: $PRIVATE_KEY_PATH"
test-run "ssh-keygen -t rsa -f ""$PRIVATE_KEY_PATH"" -q -P ''"
test-noempty "$PRIVATE_KEY_PATH" # Private key is in `----BEGIN OPENSSH PRIVATE KEY---`
test-noempty "$PUBLIC_KEY_PATH"  # Public key is in `ssh-rsa XXXX` format

test-log "Converting private key from SSH/RSA to PEM: $PRIVATE_KEY_PEM_PATH "
cp -a "$PRIVATE_KEY_PATH" "$PRIVATE_KEY_PEM_PATH"
test-run "ssh-keygen -p -m pem  -N '' -f ""$PRIVATE_KEY_PEM_PATH"
 
test-log "Generating PEM/PKCS8 public key from PEM RSA private: $PUBLIC_KEY_PKCS8_PATH"
test-run "ssh-keygen -e -f ""$PRIVATE_KEY_PATH"" -m PKCS8 > ""$PUBLIC_KEY_PKCS8_PATH"

test-noempty "$PRIVATE_KEY_PATH" "$PRIVATE_KEY_PEM_PATH" "$PUBLIC_KEY_PATH" "$PUBLIC_KEY_PKCS8_PATH"

echo "=== Private Key RSA"
head -n2 "$PRIVATE_KEY_PATH"

echo "=== Private Key PEM"
head -n2 "$PRIVATE_KEY_PEM_PATH"

echo "=== Public Key RSA"
head -n2 "$PUBLIC_KEY_PATH"

echo "=== Public Key PKCS8"
head -n2 "$PUBLIC_KEY_PKCS8_PATH"

# EOF
