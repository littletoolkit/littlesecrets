#!/bin/bash

# Array to store temporary files/directories for cleanup
declare -a _TEMP_FILES=()
declare -a _TEMP_DIRS=()

# Logging function that writes to stderr
function LOG() {
    local msg="${1:-}"
    echo "${msg}" >&2
}

function FAIL() {
    LOG "!!! FAIL: $@"
    exit 1
}

function TEST() {
	LOG "--- TEST $@"
}

# Command execution wrapper
function DO() {
    local cmd="${1}"
    if [[ -z "${cmd}" ]]; then
        LOG "-!- DO: No command provided"
        exit 1
    fi

    if eval "${cmd}"; then
		    echo ".-. OK"
    else
        local status=$?
        LOG "!!! FAIL ${cmd}"
        exit ${status}
    fi
}

# Check if file exists and is non-empty
function NO_EMPTY() {
    local path="${1}"
    if [[ -z "${path}" ]]; then
        FAIL "NO_EMPTY: No path provided"
    fi

    if [[ ! -f "${path}" ]]; then
        FAIL "NO_EMPTY: ${path} is not a file"
    fi

    if [[ ! -s "${path}" ]]; then
        FAIL "NO_EMPTY: ${path} is empty"
    fi

    LOG "OK"
}

# Create temporary file with optional prefix/suffix
function MKTEMP() {
    local prefix="${1:-}"
    local suffix="${2:-}"
    local tmp

    if [[ -n "${prefix}" ]] && [[ -n "${suffix}" ]]; then
        tmp=$(mktemp -t "${prefix}.XXXXXX${suffix}")
    elif [[ -n "${prefix}" ]]; then
        tmp=$(mktemp -t "${prefix}.XXXXXX")
    else
        tmp=$(mktemp)
    fi

    if [[ $? -ne 0 ]]; then
        LOG "Failed to create temporary file"
        exit 1
    fi

    _TEMP_FILES+=("${tmp}")
    echo "${tmp}"
}

function should-fail() {
  local RESULT
  local RET
  echo "TRY Should fail: $@"
  RESULT=$(env A=A "$@")
  RET="$?"
  if [ "$RET" == "0" ]; then
    echo "ERR Should have failed, got $RET: $@ → \"$RESULT\""
    exit 1
  else
    echo -n "$RESULT"
  fi
}

function try() {
  local RESULT
  local RET
  echo "TRY $@"
  RESULT=$(env A=A "$@")
  RET="$?"
  if [ "$RET" != "0" ]; then
    echo "ERR Failed with $RET: $@ → \"$RESULT\""
    exit 1
  else
    echo -n "$RESULT"
  fi
}



# Create temporary directory with optional prefix/suffix
function MKDTEMP() {
    local prefix="${1:-}"
    local suffix="${2:-}"
    local tmp

    if [[ -n "${prefix}" ]] && [[ -n "${suffix}" ]]; then
        tmp=$(mktemp -d -t "${prefix}.XXXXXX${suffix}")
    elif [[ -n "${prefix}" ]]; then
        tmp=$(mktemp -d -t "${prefix}.XXXXXX")
    else
        tmp=$(mktemp -d)
    fi

    if [[ $? -ne 0 ]]; then
        LOG "Failed to create temporary directory"
        exit 1
    fi

    _TEMP_DIRS+=("${tmp}")
    echo "${tmp}"
}

# Cleanup function
function testing_cleanup() {
    # Remove temporary files
    for file in "${_TEMP_FILES[@]}"; do
        [[ -f "${file}" ]] && rm -f "${file}"
    done

    # Remove temporary directories
    for dir in "${_TEMP_DIRS[@]}"; do
        [[ -d "${dir}" ]] && rm -rf "${dir}"
    done
}

# Set trap handlers for cleanup
trap testing_cleanup EXIT INT TERM

# Usage examples:
# 
# Bash
# # Source the library
# source ./utils.sh
# 
# # Log a message
# LOG "Starting process"
# 
# # Execute a command
# DO "ls -l"
# 
# # Create a temporary file
# temp_file=$(MKTEMP "myprefix" ".txt")
# echo "Working with temp file: $temp_file"
# 
# # Create a temporary directory
# temp_dir=$(MKDTEMP "mydir")
# echo "Working with temp directory: $temp_dir"
# Files and directories will be automatically cleaned up when the script exits

# EOF
