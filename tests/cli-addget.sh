#!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh

# --
# Tests add/get secrets

test-start

# --
# First step is to add/retrieve a secret
SECRET="Hello, World $(date)!"
test-step "Add secret"
ls_store_init
ls_secret_add hello.world "$SECRET"

test-step "Retrieve secret"
test-expect "$(ls_secret_get hello.world)" "$SECRET"

# --
# Second step is to generate a new private key, and make sure
# we can't decrypt the secet
test-info "Fails to retrieve secret with new private key"
test-step "Generation of a new private key"
PRIVKEY=$(ls_privkey_new)
test-info "Next command expected to fail"
if ls_secret_get hello.world "$PRIVKEY"; then
	test-fail "Should not decode secret"
else
	test-ok
fi

test-cleanup

# EOF
