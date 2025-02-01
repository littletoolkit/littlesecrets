#!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh

# --
# Tests add/get secrets

test-start

# --
# First step is to add/retrieve a secret
SECRET="Hello, World $(date)!"

test-step "Add secret"
littlesecrets init
echo -n "$SECRET" | littlesecrets add hello.world

test-step "Generates a new keypair for Alice"
ssh-keygen -t rsa -b 4096 -f alice.rsa -P ""
sed -i "s|$USER@$HOSTNAME|alice@machine|g" alice.rsa.pub
littlesecrets register alice alice.rsa.pub

test-step "Validates that I can read the secret"
test-expect "$(littlesecrets get hello.world)" "$SECRET"

test-step "Validates that Alice can't read the secret"
if [ "$(littlesecrets -u alice -k alice.rsa get hello.world)" == "$SECRET" ]; then
	test-fail "Alice should not be able to read the secret"
else
	test-ok
fi

test-step "Grants the secret to alice"
littlesecrets grant hello.world alice
test-expect "$(littlesecrets list | grep hello.world)" "hello.world: alice@machine $USER@$HOSTNAME"

test-step "Validates that alice can read the secret now"
test-expect "$(littlesecrets -u alice@machine -k alice.rsa get hello.world)" "$SECRET"

test-step "Alice can generate secret"
ALICE_SECRET="Hello from Alice $(date)"
echo -n "$ALICE_SECRET" | littlesecrets -u alice@machine -k alice.rsa add alice.secret
test-expect "$(littlesecrets -u alice@machine -k alice.rsa get alice.secret)" "$ALICE_SECRET"

test-step "I cant' get the secret"
if [ "$(littlesecrets get alice.secret)" == "$ALICE_SECRET" ]; then
	test-fail "I should not be able to read the secret"
else
	test-ok
fi

test-step "Grants the secret to me"
littlesecrets -u alice@machine -k alice.rsa grant alice.secret "$USER"
test-expect "$(littlesecrets list | grep alice.secret)" "alice.secret: alice@machine $USER@$HOSTNAME"

test-step "I can now read the secret me"
test-expect "$(littlesecrets get alice.secret)" "$ALICE_SECRET"

test-cleanup

# EOF
