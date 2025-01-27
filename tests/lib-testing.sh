#!/usr/bin/env bash

# --
# Primitives for testing

set -euo pipefail

ORIGINAL_PATH="$PWD"
ORIGINAL_TMPDIR="${TMPDIR:-/tmp}"
BASE_PATH="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_NAME="$(basename "$0" | cut -d. -f1)"
TEST_PATH=""
declare -a TEST_ERRORS=()
declare -a TEST_LOG=()
declare -a TEST_CLEAN=()
TEST_CLEAN+=("")
TEST_COUNT=0
TEST_CURRENT=0
TEST_CURRENT_ERRORS=0

# Test data is not public, so we restrict the umask.
umask 0077

# --
# Starts the test, running the test in a new temporary
# directory set to `TEST_PATH`
#
# ```
# test-start "My test"
# ```
function test-start {
	if [ -n "$TEST_PATH" ]; then
		test-cleanup
		TEST_PATH=""
		TMPDIR="$ORIGINAL_TMPDIR"
		export TMPDIR
	fi
	TEST_PATH=$(realpath $(mktemp -d -p "$ORIGINAL_PATH" -t tmp.testing.XXX))
	TMPDIR="$TEST_PATH"
	export TMPDIR
	TEST_NAME="${1:-$TEST_NAME}"
	if [ -z "$TEST_PATH" ] || [ ! -d "$TEST_PATH" ]; then
		test-error "Path empty or does not exists: '$TEST_PATH'"
		return 1
	fi
	test-log "Starting in: $TEST_PATH"
	cd "$TEST_PATH"
}

function test-diff {
	local a=$(mktemp -p "$TEST_PATH" var.XXX)
	local b=$(mktemp -p "$TEST_PATH" var.XXX)
	echo "$1" >"$a"
	echo "$2" >"$b"
	echo "--- Expected/Retrieved"
	diff "$a" "$b"
	echo "---"
	unlink "$a"
	unlink "$b"
}

function test-expect {
	if [ "$1" != "$2" ]; then
		test-fail "Output differ"
		test-diff "$1" "$2"
	else
		test-succeeds
	fi
}

function test-step {
	((TEST_COUNT += 1))
	echo "[$TEST_NAME] $(test-id) === $@"
	if [ "$TEST_CURRENT" != "$TEST_COUNT" ]; then
		if [ "$TEST_CURRENT_ERRORS" != "${#TEST_ERRORS[*]}" ]; then
			local errcount=${#TEST_ERRORS[*]}
			test-error "FAIL $((errcount - TEST_CURRENT_ERRORS)) error(s)"
		else
			test-log "OK"
		fi
	fi
	TEST_CURRENT=$TEST_COUNT
	TEST_CURRENT_ERRORS="${#TEST_ERRORS[*]}"
}

function test-id {
	printf "%03d" $TEST_CURRENT
}

function test-log {
	echo "[$TEST_NAME] $(test-id) ... $@"
}

function test-output {
	echo "[$TEST_NAME] $(test-id) >>>"
	echo "$@"
	echo "<<<"
}

function test-error {
	echo "[$TEST_NAME] $(test-id) !!! $@"
}

function test-run {
	test-log ">>> $@"
	local OUT="$(eval "$@")"
	local STATUS="$?"
	if [ "$STATUS" == 0 ]; then
		test-succeeds
	else
		test-error "Command failed [$STATUS]: $@"
		test-output "$OUT"
		test-abort
	fi
}

function test-abort {
	echo "$@" >/dev/stderr
	TEST_ERRORS+=("F${TEST_CURRENT}")
	test-cleanup
}

function test-succeeds {
	if [ ! -s "$@" ]; then echo "... $*" >/dev/stderr; fi
	TEST_LOG+=("✓${TEST_CURRENT}")
}

function test-fail {
	if [ ! -z "$@" ]; then echo "!!! FAIL $*" >/dev/stderr; fi
	TEST_LOG+=("×")
	TEST_ERRORS+=("F${TEST_CURRENT}")
}

function test-err {
	echo "$@" >/dev/stderr
	TEST_LOG+=("×")
	TEST_ERRORS+=("E${TEST_CURRENT}")
}

function test-data {
	local data_path="$BASE_PATH/tests/data/$1"
	if [ -n "$1" ] && [ -e "$data_path" ]; then
		echo -n "$data_path"
	elif [ -z "$1" ]; then
		test-err "-!- ERR 'test-data FILENAME' is missing FILENAME argument"
		exit 1
	else
		test-err "!!! ERR Could not find test data: path=$data_path"
		exit 1
	fi
}

function test-cleanup {
	if [ -e "$TEST_PATH" ]; then
		rm -rf "$TEST_PATH"
	fi
	for path in "${TEST_CLEAN[@]}"; do
		if [ -z "$path" ]; then
			path=
		elif [ -d "$path" ]; then
			rm -rf "$path"
		elif [ -e "$path" ]; then
			unlink "$path"
		fi
	done
	local sn=${#TEST_LOG[*]}
	local en=${#TEST_ERRORS[@]}
	local tn=$((sn + en))
	if [ ${#TEST_ERRORS[@]} -eq 0 ]; then
		echo "[$TEST_NAME] EOK ($sn/$tn) $((100 * sn / tn))%: ${TEST_LOG[@]}" >&2
		return 0
	else
		for err in "${TEST_ERRORS[@]}"; do
			echo "$err" >&2
		done
		echo "[$TEST_NAME] EFAIL ($en/$tn) $((100 * sn / tn))%" >&2
		return 1
	fi
}

function test-xxx() {
	local prefix="${2:-}"
	local suffix="${1:-}"
	local parent="${TEST_PATH:-/tmp}"
	test-log "TEST PATH $TEST_PATH"
	local tmp
	if [[ -n "${prefix}" ]] && [[ -n "${suffix}" ]]; then
		tmp=$(mktemp -p "$parent" -t "${prefix}.XXXXXX${suffix}")
	elif [[ -n "${prefix}" ]]; then
		tmp=$(mktemp -p "$parent" -t "${prefix}.XXXXXX")
	else
		tmp=$(mktemp)
	fi

	if [[ $? -ne 0 ]]; then
		test-abort "Failed to create temporary file"
		exit 1
	fi
	TEST_CLEAN+=("${tmp}")
	test-log "TEMP ${TEST_CLEAN[@]} ${tmp}"
	echo "${tmp}"
}

function test-path {
	if [ ! -e "$BASE_PATH/.deps/run" ]; then mkdir -p "$BASE_PATH/.deps/run"; fi
	TEST_PATH="$(mktemp -d -p "$BASE_PATH/.deps/run" "$TEST_NAME.test.XXXXX")"
	export TEST_PATH
	mkdir -p "$TEST_PATH"
	cd "$ORIGINAL_PATH"
	echo -n "$TEST_PATH"
}

function test-exist {
	for path in "$@"; do
		if [ ! -e "$path" ]; then
			test-fail "path does not exists: $path"
		else
			test-succeeds
		fi
	done
}

function test-noempty {
	for path in "$@"; do
		if [ ! -f "$path" ]; then
			test-fail "path does not exists: $path"
		elif [ ! -s "$path" ]; then
			test-fail "path is empty: $path"
		else
			test-succeeds
		fi
	done
}

function test-empty {
	local name="$1"
	local value="$2"
	local failure="$3"
	test-log "--- TEST $name"
	if [ -s "$value" ]; then
		test-fail "$failure"
	else
		test-succeeds
	fi
}

trap test-cleanup EXIT INT TERM

# EOF
