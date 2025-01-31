##!/usr/bin/env bash
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/src/sh/littlesecrets.sh

# --
# Tests the registration of users

# Initialize testing
test-init

# Test registering with default parameters (current user, current host)
test-case "Register with defaults"
littlesecrets register
test-ok
test-noempty ".littlesecrets/user/$USER/$HOSTNAME.pubkey"
# test-assert_contains "$(cat ".littlesecrets/user/$USER/$HOSTNAME.pubkey")" "ssh-rsa"

# Test registering with explicit user
test-case "Register with explicit user"
littlesecrets register alice
test-ok
test-noempty ".littlesecrets/user/alice/$HOSTNAME.pubkey"

# Test registering with user@host format
test-case "Register with user@host"
littlesecrets register bob@laptop
test-ok
test-noempty ".littlesecrets/user/bob/laptop.pubkey"

# Test registering with --user and --host options
test-case "Register with --user and --host options"
littlesecrets --user carol --host desktop register
test-ok
test-noempty ".littlesecrets/user/carol/desktop.pubkey"

# Test registering with explicit key file
test-case "Register with explicit key file"
ssh-keygen -t rsa -N "" -f "test-key"
littlesecrets register dave@server test-key.pub
test-ok
test-noempty ".littlesecrets/user/dave/server.pubkey"
rm -f "test-key" "test_key.pub"

# Test registering with --key option
test-case "Register with --key option"
ssh-keygen -t rsa -N "" -f "test-key2"
littlesecrets --key test-key2.pub register eve@cloud
test-ok
test-noempty ".littlesecrets/user/eve/cloud.pubkey"
rm -f "test-key2" "test_key2.pub"

# Test overwriting existing registration
test-case "Overwrite existing registration"
littlesecrets register frank@desktop
test-ok
test-noempty ".littlesecrets/user/frank/desktop.pubkey"
first_key="$(cat .littlesecrets/user/frank/desktop.pubkey)"
ssh-keygen -t rsa -N "" -f "new_key"
littlesecrets register frank@desktop new_key.pub
test-ok
test-noempty ".littlesecrets/user/frank/desktop.pubkey"
second_key="$(cat .littlesecrets/user/frank/desktop.pubkey)"
test-assert_not_equals "$first_key" "$second_key"
rm -f "new_key" "new_key.pub"

# Test error cases
test-case "Register with invalid key file"
littlesecrets register grace@server /nonexistent/key.pub
test-assert_failure

# Cleanup
test-cleanup

# EOF
