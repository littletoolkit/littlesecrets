#!/usr/bin/env bash
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

# --
# Tests JSON output format functionality

test-start

# Capture the current user@host for test assertions
CURRENT_USER="${LITTLESECRETS_USER:-$USER}"
CURRENT_HOST="${LITTLESECRETS_HOST:-$HOSTNAME}"
CURRENT_USER_HOST="${CURRENT_USER}@${CURRENT_HOST}"
CURRENT_USER_COLON="${CURRENT_USER}:${CURRENT_HOST}"

test-step "Init store"
ls_store_init || test-fail "Could not init store"

# Create test users with different hosts
test-step "Register additional test users"
PRIVKEY1=$(test-expect-success ls_privkey_new)
PUBKEY1=$(test-expect-success ls_pubkey_import "$PRIVKEY1")
ls_cli register user1@host1 "$PUBKEY1" || test-fail "Could not register user1@host1"

PRIVKEY2=$(test-expect-success ls_privkey_new)
PUBKEY2=$(test-expect-success ls_pubkey_import "$PRIVKEY2")
ls_cli register user2@host2 "$PUBKEY2" || test-fail "Could not register user2@host2"

# Create test secrets
test-step "Create test secrets"
ls_cli add secret1 "value1" || test-fail "Could not add secret1"
ls_cli add secret2 "value2" || test-fail "Could not add secret2"
ls_cli add binary-secret $'binary\x00data' || test-fail "Could not add binary secret"

# Grant access to additional users
ls_cli grant secret1 "user1@host1" || test-fail "Could not grant access to user1@host1"
ls_cli grant secret2 "user1@host1 user2@host2" || test-fail "Could not grant access to multiple users"
ls_cli grant binary-secret "user2@host2" || test-fail "Could not grant access to user2@host2 for binary-secret"

test-step "Test JSON format for list command"
JSON_LIST=$(ls_cli -f json list)
echo "$JSON_LIST" | grep -q '"secret1"' || test-fail "JSON list should contain secret1"
echo "$JSON_LIST" | grep -q '"secret2"' || test-fail "JSON list should contain secret2"
echo "$JSON_LIST" | grep -q '"binary-secret"' || test-fail "JSON list should contain binary-secret"
echo "$JSON_LIST" | grep -q "\"$CURRENT_USER_HOST\"" || test-fail "JSON list should contain current user"
# Verify it's valid JSON structure
echo "$JSON_LIST" | grep -q '{' || test-fail "JSON list should start with brace"
echo "$JSON_LIST" | grep -q '}' || test-fail "JSON list should end with brace"
echo "$JSON_LIST" | grep -q '\[' || test-fail "JSON list should contain array bracket for users"

test-step "Test JSON format for get command with text secret"
JSON_GET=$(ls_cli -f json get secret1)
echo "$JSON_GET" | grep -q '"name"' || test-fail "JSON get should contain name field"
echo "$JSON_GET" | grep -q '"secret1"' || test-fail "JSON get should contain secret name"
echo "$JSON_GET" | grep -q '"value"' || test-fail "JSON get should contain value field"
echo "$JSON_GET" | grep -q '"value1"' || test-fail "JSON get should contain secret value"
# Verify it's valid JSON structure
echo "$JSON_GET" | grep -q '{' || test-fail "JSON get should start with brace"
echo "$JSON_GET" | grep -q '}' || test-fail "JSON get should end with brace"
# Should not contain encoding field for text data
echo "$JSON_GET" | grep -q '"encoding"' && test-fail "Text secret should not have encoding field"

test-step "Test JSON format for add command"
JSON_ADD=$(ls_cli -f json add json-added-secret added-value)
echo "$JSON_ADD" | grep -q '"name"' || test-fail "JSON add should contain name field"
echo "$JSON_ADD" | grep -q '"json-added-secret"' || test-fail "JSON add should contain secret name"
echo "$JSON_ADD" | grep -q '"value"' || test-fail "JSON add should contain value field"
echo "$JSON_ADD" | grep -q '"added-value"' || test-fail "JSON add should contain secret value"
# Should not contain encoding for text
echo "$JSON_ADD" | grep -q '"encoding"' && test-fail "Text add should not have encoding field"

# Test set (update) with stdin
TEST_SET_VALUE="updated-value"
JSON_SET=$(echo -n "$TEST_SET_VALUE" | ls_cli -f json set json-added-secret)
echo "$JSON_SET" | grep -q '"json-added-secret"' || test-fail "JSON set should contain secret name"
echo "$JSON_SET" | grep -q '"updated-value"' || test-fail "JSON set should contain updated value"

# TODO: Do re-enabled when binary is implemented
# # Binary add - create binary data using printf to temp file
# BINARY_FILE=$(mktemp)
# printf 'bin\x00val' > "$BINARY_FILE"
# JSON_ADD_BIN=$(cat "$BINARY_FILE" | ls_cli -f json add json-bin-secret)
# rm "$BINARY_FILE"
# echo "$JSON_ADD_BIN" | grep -q '"json-bin-secret"' || test-fail "JSON add binary should contain secret name"
# echo "$JSON_ADD_BIN" | grep -q '"encoding"' || test-fail "Binary add should have encoding field"
#
# # Binary set via stdin - create binary data using printf to temp file
# BINARY_SET_FILE=$(mktemp)
# printf 'more\x00bin' > "$BINARY_SET_FILE"
# JSON_SET_BIN=$(cat "$BINARY_SET_FILE" | ls_cli -f json set json-bin-secret)
# rm "$BINARY_SET_FILE"
# echo "$JSON_SET_BIN" | grep -q '"json-bin-secret"' || test-fail "JSON set binary should contain secret name"
# echo "$JSON_SET_BIN" | grep -q '"encoding"' || test-fail "Binary set should have encoding field"

test-step "Test JSON format for ensure command with existing secret"
JSON_ENSURE=$(ls_cli -f json ensure secret1)
echo "$JSON_ENSURE" | grep -q '"name"' || test-fail "JSON ensure should contain name field"
echo "$JSON_ENSURE" | grep -q '"secret1"' || test-fail "JSON ensure should contain secret name"
echo "$JSON_ENSURE" | grep -q '"value"' || test-fail "JSON ensure should contain value field"
echo "$JSON_ENSURE" | grep -q '"value1"' || test-fail "JSON ensure should contain existing secret value"

test-step "Test JSON format for ensure command with new secret"
JSON_ENSURE_NEW=$(ls_cli -f json ensure new-secret)
echo "$JSON_ENSURE_NEW" | grep -q '"name"' || test-fail "JSON ensure should contain name field"
echo "$JSON_ENSURE_NEW" | grep -q '"new-secret"' || test-fail "JSON ensure should contain new secret name"
echo "$JSON_ENSURE_NEW" | grep -q '"value"' || test-fail "JSON ensure should contain value field"
# New secret should be 16 characters
ENSURE_VALUE=$(echo "$JSON_ENSURE_NEW" | grep -o '"value": "[^"]*"' | cut -d'"' -f4)
if [ ${#ENSURE_VALUE} -ne 16 ]; then
	test-fail "New secret should be 16 characters, got ${#ENSURE_VALUE}"
fi

test-step "Test JSON format for users command"
JSON_USERS=$(ls_cli -f json users)
echo "$JSON_USERS" | grep -q "\"$CURRENT_USER\"" || test-fail "JSON users should contain current user"
echo "$JSON_USERS" | grep -q '"user1"' || test-fail "JSON users should contain user1"
echo "$JSON_USERS" | grep -q '"user2"' || test-fail "JSON users should contain user2"
echo "$JSON_USERS" | grep -q "\"$CURRENT_HOST\"" || test-fail "JSON users should contain current host"
echo "$JSON_USERS" | grep -q '"host1"' || test-fail "JSON users should contain host1"
echo "$JSON_USERS" | grep -q '"host2"' || test-fail "JSON users should contain host2"
# Verify it's valid JSON structure
echo "$JSON_USERS" | grep -q '{' || test-fail "JSON users should start with brace"
echo "$JSON_USERS" | grep -q '}' || test-fail "JSON users should end with brace"
echo "$JSON_USERS" | grep -q '\[' || test-fail "JSON users should contain array brackets"

test-step "Test JSON format for access command"
JSON_ACCESS=$(ls_cli -f json access)
echo "$JSON_ACCESS" | grep -q '"secret1"' || test-fail "JSON access should contain secret1"
echo "$JSON_ACCESS" | grep -q '"secret2"' || test-fail "JSON access should contain secret2"
echo "$JSON_ACCESS" | grep -q '"binary-secret"' || test-fail "JSON access should contain binary-secret"
echo "$JSON_ACCESS" | grep -q "\"$CURRENT_USER_HOST\"" || test-fail "JSON access should contain current user"
echo "$JSON_ACCESS" | grep -q '"user1@host1"' || test-fail "JSON access should contain user1@host1"
echo "$JSON_ACCESS" | grep -q '"user2@host2"' || test-fail "JSON access should contain user2@host2"
# Verify it's valid JSON structure
echo "$JSON_ACCESS" | grep -q '{' || test-fail "JSON access should start with brace"
echo "$JSON_ACCESS" | grep -q '}' || test-fail "JSON access should end with brace"

test-step "Test JSON format for export command"
JSON_EXPORT=$(ls_cli -f json export)
echo "$JSON_EXPORT" | grep -q '\[' || test-fail "JSON export should start with array bracket"
echo "$JSON_EXPORT" | grep -q '\]' || test-fail "JSON export should end with array bracket"
echo "$JSON_EXPORT" | grep -q '{' || test-fail "JSON export should contain object braces"
echo "$JSON_EXPORT" | grep -q '}' || test-fail "JSON export should contain object braces"
echo "$JSON_EXPORT" | grep -q '"name"' || test-fail "JSON export should contain name fields"
echo "$JSON_EXPORT" | grep -q '"value"' || test-fail "JSON export should contain value fields"
# Should contain all secrets
echo "$JSON_EXPORT" | grep -q '"secret1"' || test-fail "JSON export should contain secret1"
echo "$JSON_EXPORT" | grep -q '"secret2"' || test-fail "JSON export should contain secret2"
echo "$JSON_EXPORT" | grep -q '"binary-secret"' || test-fail "JSON export should contain binary-secret"

test-step "Test JSON format for specific secret export"
JSON_EXPORT_SPECIFIC=$(ls_cli -f json export TEST_EXPORT=secret1)
echo "$JSON_EXPORT_SPECIFIC" | grep -q '\[' || test-fail "JSON export specific should start with array bracket"
echo "$JSON_EXPORT_SPECIFIC" | grep -q '\]' || test-fail "JSON export specific should end with array bracket"
echo "$JSON_EXPORT_SPECIFIC" | grep -q '"secret1"' || test-fail "JSON export specific should contain secret1"
echo "$JSON_EXPORT_SPECIFIC" | grep -q '"secret2"' && test-fail "JSON export specific should not contain secret2"

test-step "Test that default text format still works"
TEXT_LIST=$(ls_cli list)
echo "$TEXT_LIST" | grep -q 'secret1' || test-fail "Text list should contain secret1"
echo "$TEXT_LIST" | grep -q 'secret2' || test-fail "Text list should contain secret2"
echo "$TEXT_LIST" | grep -q "$CURRENT_USER_HOST" || test-fail "Text list should contain user info"

TEXT_GET=$(ls_cli get secret1)
test-expect "$TEXT_GET" "value1" "Text get should return plain value"

TEXT_USERS=$(ls_cli users)
echo "$TEXT_USERS" | grep -q "$CURRENT_USER_COLON" || test-fail "Text users should contain user:host format"

TEXT_ACCESS=$(ls_cli access)
echo "$TEXT_ACCESS" | grep -q 'secret1:' || test-fail "Text access should contain secret1:"
echo "$TEXT_ACCESS" | grep -q "$CURRENT_USER_HOST" || test-fail "Text access should contain user info"

TEXT_EXPORT=$(ls_cli export)
echo "$TEXT_EXPORT" | grep -q "export SECRET1='value1'" || test-fail "Text export should contain shell export format"

# Test forced binary encoding for a text secret
TEST_FORCE_BIN=$(ls_cli -f json --binary get secret1)
if ! echo "$TEST_FORCE_BIN" | grep -q '"encoding"'; then
	test-fail "--binary should force encoding field for text secret"
fi
# Test forced text decoding for a binary secret
TEST_FORCE_TEXT=$(ls_cli -f json --text get binary-secret)
if echo "$TEST_FORCE_TEXT" | grep -q '"encoding"'; then
	test-fail "--text should suppress encoding field for binary secret"
fi

test-step "Test JSON format validation with jq (if available)"
if command -v jq >/dev/null 2>&1; then
	echo "$JSON_LIST" | jq . >/dev/null 2>&1 || test-fail "JSON list output should be valid JSON"
	echo "$JSON_GET" | jq . >/dev/null 2>&1 || test-fail "JSON get output should be valid JSON"
	echo "$JSON_ENSURE" | jq . >/dev/null 2>&1 || test-fail "JSON ensure output should be valid JSON"
	echo "$JSON_USERS" | jq . >/dev/null 2>&1 || test-fail "JSON users output should be valid JSON"
	echo "$JSON_ACCESS" | jq . >/dev/null 2>&1 || test-fail "JSON access output should be valid JSON"
	echo "$JSON_EXPORT" | jq . >/dev/null 2>&1 || test-fail "JSON export output should be valid JSON"
	test-ok "All JSON outputs validated successfully with jq"
else
	test-info "jq not available, skipping JSON validation"
fi

test-step "Test error handling in JSON format"
# Test with non-existent secret - should fail but error message should be in stderr
if ls_cli -f json get non-existent-secret 2>/dev/null; then
	test-fail "JSON get of non-existent secret should fail"
else
	test-ok "JSON get of non-existent secret correctly failed"
fi

# Test with invalid format option (should show error)
if ls_cli --format=invalid list >/dev/null 2>&1; then
	test-fail "Invalid format option should fail"
else
	test-ok "Invalid format option correctly failed"
fi

# EOF

