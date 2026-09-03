#!/usr/bin/env bash
# shellcheck disable=SC1091
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/src/sh/littlesecrets.sh"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Render formatted help"
HELP_OUTPUT="$(ls_cli help)"

echo "$HELP_OUTPUT" | grep -q '^Usage: littlesecrets \[GLOBAL_OPTION\]\.\.\. COMMAND \[ARGUMENT\]\.\.\.$' || test-fail "help should show usage"
echo "$HELP_OUTPUT" | grep -q '^Version: 1\.1\.0$' || test-fail "help should show the CLI version"
echo "$HELP_OUTPUT" | grep -q '^  -h, --help                 Show this help message$' || test-fail "options should be aligned"
echo "$HELP_OUTPUT" | grep -q "^  --host HOST                Set the host name (default: [\$]HOSTNAME)$" || test-fail "host option should be aligned"
echo "$HELP_OUTPUT" | grep -q '^Meta:$' || test-fail "help should contain command groups"
echo "$HELP_OUTPUT" | grep -q '^  help \[COMMAND\][[:space:]]\+Show help for a command$' || test-fail "commands should be grouped and aligned"
echo "$HELP_OUTPUT" | grep -q '^  hash \[SECRET_EXPR\.\.\.\][[:space:]]\+Create or update HMACs$' || test-fail "hash syntax should be normalized"
echo "$HELP_OUTPUT" | grep -q '^  info[[:space:]]\+Show the active and ancestor stores$' || test-fail "last command should be formatted"

test-step "Render command-specific help"
GET_HELP="$(ls_cli get --help)"
echo "$GET_HELP" | grep -q '^Usage: littlesecrets get <SECRET>$' || test-fail "command help should show usage"
echo "$GET_HELP" | grep -q '^Write a secret value$' || test-fail "command help should show description"

if echo "$HELP_OUTPUT" | grep -q '^help              '; then

	test-fail "commands should not use the old unindented layout"
fi

test-step "Reject invalid CLI contracts"
if ls_cli --format yaml help >/dev/null 2>&1; then
	test-fail "invalid output formats should fail"
fi
if ls_cli --binary help >/dev/null 2>&1; then
	test-fail "binary mode outside JSON should fail"
fi
if ls_cli get one two three >/dev/null 2>&1; then
	test-fail "unexpected positional arguments should fail"
fi
