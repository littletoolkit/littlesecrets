#!/usr/bin/env bash
# Test the register command

# Source the testing library
. "$(dirname "$0")/lib-testing.sh"

# Initialize testing
test_init

# Test registering with default parameters (current user, current host)
test_case "Register with defaults"
littlesecrets register
test_assert_success
test_assert_file_exists ".littlesecrets/user/$USER/$HOSTNAME.pubkey"
test_assert_contains "$(cat ".littlesecrets/user/$USER/$HOSTNAME.pubkey")" "ssh-rsa"

# Test registering with explicit user
test_case "Register with explicit user"
littlesecrets register alice
test_assert_success
test_assert_file_exists ".littlesecrets/user/alice/$HOSTNAME.pubkey"

# Test registering with user@host format
test_case "Register with user@host"
littlesecrets register bob@laptop
test_assert_success
test_assert_file_exists ".littlesecrets/user/bob/laptop.pubkey"

# Test registering with --user and --host options
test_case "Register with --user and --host options"
littlesecrets --user carol --host desktop register
test_assert_success
test_assert_file_exists ".littlesecrets/user/carol/desktop.pubkey"

# Test registering with explicit key file
test_case "Register with explicit key file"
ssh-keygen -t rsa -N "" -f "/tmp/test_key"
littlesecrets register dave@server /tmp/test_key.pub
test_assert_success
test_assert_file_exists ".littlesecrets/user/dave/server.pubkey"
rm -f "/tmp/test_key" "/tmp/test_key.pub"

# Test registering with --key option
test_case "Register with --key option"
ssh-keygen -t rsa -N "" -f "/tmp/test_key2"
littlesecrets --key /tmp/test_key2.pub register eve@cloud
test_assert_success
test_assert_file_exists ".littlesecrets/user/eve/cloud.pubkey"
rm -f "/tmp/test_key2" "/tmp/test_key2.pub"

# Test overwriting existing registration
test_case "Overwrite existing registration"
littlesecrets register frank@desktop
test_assert_success
test_assert_file_exists ".littlesecrets/user/frank/desktop.pubkey"
first_key="$(cat .littlesecrets/user/frank/desktop.pubkey)"
ssh-keygen -t rsa -N "" -f "/tmp/new_key"
littlesecrets register frank@desktop /tmp/new_key.pub
test_assert_success
test_assert_file_exists ".littlesecrets/user/frank/desktop.pubkey"
second_key="$(cat .littlesecrets/user/frank/desktop.pubkey)"
test_assert_not_equals "$first_key" "$second_key"
rm -f "/tmp/new_key" "/tmp/new_key.pub"

# Test error cases
test_case "Register with invalid key file"
littlesecrets register grace@server /nonexistent/key.pub
test_assert_failure

# Cleanup
test_cleanup
