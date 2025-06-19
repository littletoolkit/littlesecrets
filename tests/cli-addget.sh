#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

# --
# Tests add/get secrets

test-start

# --
# First step is to add/retrieve a secret
SECRET="Hello, World $(date)!"
test-step "Add secret"
ls_store_init || test-fail

test-step "Ensures the secret files are there"
echo -n "$SECRET" | ls_secret_add hello.world || test-fail
test-exist .littlesecrets/secret/hello.world/secret.enc
test-exist .littlesecrets/secret/hello.world/"$USER"@"$HOSTNAME".key
test-step "Ensures the user has a public key"
test-exist .littlesecrets/user/"$USER"/"$HOSTNAME".pubkey

test-step "Retrieve secret"
test-expect "$(ls_secret_list | grep hello.world)" "hello.world"
test-expect "$(ls_secret_get hello.world)" "$SECRET"

# --
# Second step is to generate a new private key, and make sure
# we can't decrypt the secet
test-step "Generation of a new private key"
PRIVKEY=$(test-expect-success ls_privkey_new)

test-step "Next command expected to fail"
test-expect-failure ls_secret_get hello.world "$PRIVKEY"

# EOF
