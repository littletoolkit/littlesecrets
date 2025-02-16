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

# --
# Color library
if [ -z "${NOCOLOR:-}" ]; then
	CYAN="$(tput setaf 33)"
	BLUE_DK="$(tput setaf 27)"
	BLUE="$(tput setaf 33)"
	BLUE_LT="$(tput setaf 117)"
	GREEN="$(tput setaf 34)"
	YELLOW="$(tput setaf 220)"
	GRAY="$(tput setaf 153)"
	GOLD="$(tput setaf 214)"
	GOLD_DK="$(tput setaf 208)"
	PURPLE_DK="$(tput setaf 55)"
	PURPLE="$(tput setaf 92)"
	PURPLE_LT="$(tput setaf 163)"
	RED="$(tput setaf 124)"
	ORANGE="$(tput setaf 202)"
	BOLD="$(tput bold)"
	DIM="$(tput dim)"
	REVERSE="$(tput rev)"
	RESET="$(tput sgr0)"
elif tput setaf 1 &>/dev/null; then
	CYAN=""
	BLUE_DK=""
	BLUE=""
	BLUE_LT=""
	GREEN=""
	YELLOW=""
	GOLD=""
	GOLD_DK=""
	PURPLE_DK=""
	PURPLE=""
	PURPLE_LT=""
	RED=""
	ORANGE=""
	BOLD=""
	DIM=""
	REVERSE=""
	RESET=""
fi
export CYAN BLUE_DK
export BLUE
export BLUE_LT
export GREEN
export GRAY
export YELLOW
export GOLD
export GOLD_DK
export PURPLE_DK
export PURPLE
export PURPLE_LT
export RED
export ORANGE
export BOLD
export REVERSE
export RESET

# Test data is not public, so we restrict the umask.
umask 0077

function test-init {
	test-start "$@"
	# We ensure the exit is called
	trap test-cleanup EXIT INT TERM ERR
}

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
	echo "--- Expected/Retrieved" >&2
	diff "$a" "$b" >&2
	echo "---" >&2
	unlink "$a"
	unlink "$b"
}

function test-expect {
	if [ "$1" != "$2" ]; then
		test-fail "Output differ" "${3:-}"
		echo -n "$ORANGE" >&2
		test-diff "$1" "$2"
		echo "$RESET" >&2
	else
		test-ok "${3:-}"
	fi
}

function test-case {
	test-step "$@"
}

function test-step {
	((TEST_COUNT += 1))
	echo "$(test-prefix)${BLUE} === ${BOLD}$@${RESET}" >&2

	if [ "$TEST_CURRENT" != "$TEST_COUNT" ]; then
		if [ "$TEST_CURRENT_ERRORS" != "${#TEST_ERRORS[*]}" ]; then
			local errcount=${#TEST_ERRORS[*]}
			test-error "FAIL $((errcount - TEST_CURRENT_ERRORS)) error(s)"
		fi
	fi
	TEST_CURRENT=$TEST_COUNT
	TEST_CURRENT_ERRORS="${#TEST_ERRORS[*]}"
}

function test-id {
	printf "%03d" $TEST_CURRENT
}

function test-log {
	echo "$(test-prefix) ... $@" >&2
}

function test-output {
	echo "$(test-prefix) >>>" >&2
	echo "$@" >&2
	echo "<<<" >&2
}

function test-info {
	echo "$(test-prefix)   → $@" >&2
}

function test-prefix {
	echo -n "${BLUE}${DIM}[$TEST_NAME] ${BOLD}$(test-id)${RESET}"
}

function test-error {
	echo "$(test-prefix)${RED} !!! $@${RESET}" >&2
}

function test-run {
	test-log ">>> $@"
	local OUT="$(eval "$@")"
	local STATUS="$?"
	if [ "$STATUS" == 0 ]; then
		test-ok
	else
		test-error "Command failed [$STATUS]: $@"
		test-output "$OUT"
		test-abort
	fi
}

function test-abort {
	echo "$@" >&2
	TEST_LOG+=("☇")
	TEST_ERRORS+=($(test-id))
	test-cleanup
}

function test-ok {
	if [ -n "$@" ]; then
		echo "$(test-prefix)${GREEN}   ✓ ${RESET}${DIM}$@${RESET}" >&2
	fi
	TEST_LOG+=("✓${TEST_CURRENT}")
}

function test-fail {
	if [ -n "${1:-}" ]; then
		echo "$(test-prefix)${RED} !!! FAIL $@${RESET}" >&2
	fi
	TEST_LOG+=("×")
	TEST_ERRORS+=($(test-id))
}

function test-err {
	echo "$@" >&2
	TEST_LOG+=("×")
	TEST_ERRORS+=($(test-id))
}

function test-data {
	local data_path="$BASE_PATH/tests/data/$1"
	if [ -n "$1" ] && [ -e "$data_path" ]; then
		echo -n "$data_path" >&2
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
	if [ "$tn" == 0 ]; then
		echo "${BLUE}[$TEST_NAME] ${GREEN}${BOLD}EOK (0/0)${RESET}" >&2
	elif [ ${#TEST_ERRORS[@]} -eq 0 ]; then
		echo "${BLUE}[$TEST_NAME] ${GREEN}${BOLD}EOK${RESET}${GREEN} ($sn/$tn) $((100 * sn / tn))%: ${TEST_LOG[@]}${RESET}" >&2
		return 0
	else
		echo "${BLUE}[$TEST_NAME] ${RED}FAIL  ${BOLD}${TEST_ERRORS[@]}${RESET}" >&2
		echo "${BLUE}[$TEST_NAME] ${ORANGE}${BOLD}EFAIL${RESET}${RED} ($en/$tn) $((100 * sn / tn))%${RESET}" >&2
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

function test-relpath {
	realpath --relative-to="$PWD" "$1"
}

function test-substring { # STRING STRING…
	local str="$1"
	shift
	for expr in "$@"; do
		if ! grep -q "$expr" <(echo "$str"); then
			test-fail "'$str' does not contain: '$expr'"
			return 1
		fi
	done
	return 0

}

function test-contains { # PATH STRING…
	local path="$1"
	shift
	if [ -e "$path" ]; then
		test-fail "$(test-relpath "$path") does not exist"
		return 1
	else
		for expr in "$@"; do
			if ! grep -q "$expr" "$path"; then
				test-fail "$(test-relpath "$path") does not contain: $expr"
				return 1
			fi
		done
		return 0
	fi
}

function test-exist {
	for path in "$@"; do
		if [ ! -e "$path" ]; then
			test-fail "path does not exists: $path"
			return 1
		else
			test-ok "$(test-relpath "$path") exists"
		fi
	done
	return 0
}

function test-noempty {
	for path in "$@"; do
		if [ ! -f "$path" ]; then
			test-fail "path does not exists: $path"
		elif [ ! -s "$path" ]; then
			test-fail "path is empty: $path"
		else
			test-ok
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
		test-ok
	fi
}

trap test-cleanup EXIT INT TERM ERR

# EOF
