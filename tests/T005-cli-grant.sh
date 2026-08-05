#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

# --
# Testing the granting of secrets, and making sure that only the required
# user has access

test-start

# --
# First step is to add/retrieve a secret
SECRET="Hello, World $(date)!"

# -----------------------------------------------------------------------------
#
# ALICE
#
# -----------------------------------------------------------------------------

test-step "Add secret"
test-expect-success littlesecrets init
echo -n "$SECRET" | test-expect-success littlesecrets add hello.world

test-step "Generates a new keypair for Alice"
test-expect-success ssh-keygen -t rsa -b 4096 -f alice.rsa -P "" -C "alice@machine"
test-expect-success littlesecrets register alice alice.rsa.pub

test-step "Validates that I can read the secret"
test-expect "$(littlesecrets get hello.world)" "$SECRET" "Success can be read"

test-step "Validates that Alice can't read the secret"
if test-expect-failure littlesecrets -u alice -k alice.rsa get hello.world; then
	test_log_success "Alice can't read the secret"
fi

test-step "Grants the secret to alice"
littlesecrets grant hello.world alice
# Use grep to match just the content without worrying about formatting
if littlesecrets list | grep -q "hello.world.*alice@machine"; then
	test-ok "Secret granted to alice correctly"
else
	test-fail "Secret not granted to alice correctly"
fi

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
	test-ok "Secret is only accessible to Alice"
fi

test-step "Grants the secret to me"
littlesecrets -u alice@machine -k alice.rsa grant alice.secret "$USER"
if test-expect "$(littlesecrets list | grep alice.secret | test_nocolor)" "alice.secret: alice@machine $USER@$HOSTNAME"; then
	test_log_success "Secret granted"
fi

test-step "I can now read the secret me"
if test-expect "$(littlesecrets get alice.secret)" "$ALICE_SECRET"; then
	test_log_success "Secret granted can be read"
fi

# Test wildcard support in secret names
test-step "Create multiple secrets with a common prefix"
PREFIX_SECRET1="Prefix Secret 1 $(date)"
PREFIX_SECRET2="Prefix Secret 2 $(date)"
echo -n "$PREFIX_SECRET1" | littlesecrets add prefix.secret1
echo -n "$PREFIX_SECRET2" | littlesecrets add prefix.secret2

# -----------------------------------------------------------------------------
#
# BOB
#
# -----------------------------------------------------------------------------

test-step "Verify Bob can't access the prefix secrets"
ssh-keygen -t rsa -b 4096 -f bob.rsa -P "" -C bob@machine
test-expect-success littlesecrets register bob bob.rsa.pub

if [ "$(littlesecrets -u bob@machine -k bob.rsa get prefix.secret1)" == "$PREFIX_SECRET1" ]; then
	test-fail "Bob should not be able to read prefix.secret1"
else
	test-ok "Bob correctly cannot read prefix.secret1"
fi

test-step "Grant all prefix.* secrets to Bob using wildcard"
test-expect-success littlesecrets grant 'prefix.*' bob

test-step "Verify Bob can now access both prefix secrets"
if [ "$(littlesecrets -u bob@machine -k bob.rsa get prefix.secret1)" = "$PREFIX_SECRET1" ]; then
	test-ok "Bob can access prefix.secret1"
else
	test-fail "Bob cannot access prefix.secret1"
fi

if [ "$(littlesecrets -u bob@machine -k bob.rsa get prefix.secret2)" = "$PREFIX_SECRET2" ]; then
	test-ok "Bob can access prefix.secret2"
else
	test-fail "Bob cannot access prefix.secret2"
fi

# -----------------------------------------------------------------------------
#
# CHARLIE
#
# -----------------------------------------------------------------------------

test-step "Create more secrets with different prefixes"
echo -n "Test Secret 1" | littlesecrets add test.secret1
echo -n "Test Secret 2" | littlesecrets add test.secret2
echo -n "Other Secret" | littlesecrets add other.secret
#
test-step "Create Charlie user who has no access"
ssh-keygen -t rsa -b 4096 -f charlie.rsa -P "" -C charlie@machine
test-expect-success littlesecrets register charlie charlie.rsa.pub

test-step "Grant hello.world to every registered user"
ALL_GRANT_ERR=$(littlesecrets grant hello.world '*' 2>&1 >/dev/null)
if echo "$ALL_GRANT_ERR" | grep -q "ERR.*Granted access to secret 'hello.world'"; then
	test-ok "New grants are reported on ERR output"
else
	test-fail "New grants should be reported on ERR output"
fi

test-step "Verify every registered user can access hello.world"
if [ "$(littlesecrets -u bob@machine -k bob.rsa get hello.world)" = "$SECRET" ] && \
	[ "$(littlesecrets -u charlie@machine -k charlie.rsa get hello.world)" = "$SECRET" ]; then
	test-ok "Every registered user can access hello.world"
else
	test-fail "Not every registered user can access hello.world"
fi

test-step "Repeat grant without reporting existing access"
REPEAT_GRANT_ERR=$(littlesecrets grant hello.world '*' 2>&1 >/dev/null)
if echo "$REPEAT_GRANT_ERR" | grep -q "Granted access"; then
	test-fail "Existing grants should not be reported as new"
else
	test-ok "Existing grants are not reported as new"
fi

test-step "Grant all secrets to Charlie using * wildcard"
test-expect-success littlesecrets grant '*' charlie

test-step "Verify Charlie can access all secrets"
# Check each secret individually to isolate any failures
if [ "$(littlesecrets -u charlie@machine -k charlie.rsa get hello.world)" = "$SECRET" ]; then
	test-ok "Charlie can access hello.world"
else
	test-fail "Charlie cannot access hello.world"
fi

if [ "$(littlesecrets -u charlie@machine -k charlie.rsa get alice.secret)" = "$ALICE_SECRET" ]; then
	test-ok "Charlie can access alice.secret"
else
	test-fail "Charlie cannot access alice.secret"
fi

if [ "$(littlesecrets -u charlie@machine -k charlie.rsa get prefix.secret1)" = "$PREFIX_SECRET1" ]; then
	test-ok "Charlie can access prefix.secret1"
else
	test-fail "Charlie cannot access prefix.secret1"
fi

if [ "$(littlesecrets -u charlie@machine -k charlie.rsa get test.secret1)" = "Test Secret 1" ]; then
	test-ok "Charlie can access test.secret1"
else
	test-fail "Charlie cannot access test.secret1"
fi

if [ "$(littlesecrets -u charlie@machine -k charlie.rsa get other.secret)" = "Other Secret" ]; then
	test-ok "Charlie can access other.secret"
else
	test-fail "Charlie cannot access other.secret"
fi

# EOF
