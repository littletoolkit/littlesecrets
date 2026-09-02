#!/usr/bin/env bash
#  _ _ _   _   _      __                    _
# | (_) |_| |_| | ___/ _\ ___  ___ _ __ ___| |_ ___
# | | | __| __| |/ _ \ \ / _ \/ __| '__/ _ \ __/ __|
# | | | |_| |_| |  __/\ \  __/ (__| | |  __/ |_\__ \
# |_|_|\__|\__|_|\___\__/\___|\___|_|  \___|\__|___/
#
# (c) LittleWorshop Ltd, 2025, BSD 3-Clause License

# TODO: We should never check if the key a path by using -f, this will leak the key to the OS
# TODO: Use `-A` in base64 to suppress trailing newline
# TODO: Add a signature option to validate the original secret

# --
# A simplified, reduced version of LittleSecrets that works only with
# the shell and simple tools.

set -euo pipefail
shopt -s extglob
umask 077

# --
# We define the main internal variables
declare -a LS_CLEANUP=()
LS_CLEANUP+=("")

LITTLESECRETS_VERSION="1.0.1"

# --
# And define the configuration
LITTLESECRETS_USER=${LITTLESECRETS_USER:-$USER}
LITTLESECRETS_HOST=${LITTLESECRETS_HOST:-$HOSTNAME}
LITTLESECRETS_KEY=${LITTLESECRETS_KEY:-$HOME/.ssh/id_rsa}
LITTLESECRETS_STORE_NAME=".littlesecrets"
LITTLESECRETS_STORE=${LITTLESECRETS_STORE:-$LITTLESECRETS_STORE_NAME}
LITTLESECRETS_KEYSIZE=${LITTLESECRETS_KEYSIZE:-2048} # NOTE: It would be best to do 4096, and we should test keys
LITTLESECRETS_FORMAT=${LITTLESECRETS_FORMAT:-}
LITTLESECRETS_FORCE_ENCODING=${LITTLESECRETS_FORCE_ENCODING:-}
LITTLESECRETS_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
# --
# Validate and secure the OpenSSL binary path
function ls_validate_openssl_bin {
	local bin="${1:-openssl}"
	local resolved_bin=""
	
	# Check for command injection attempts (spaces, semicolons, pipes, redirects, etc.)
	if [[ "$bin" =~ [[:space:]\;\|\&\$\`\<\>] ]]; then
		echo "SECURITY ERROR: LITTLESECRETS_OPENSSL_BIN contains invalid characters: $bin" >&2
		echo "The OpenSSL binary path must not contain spaces, semicolons, pipes, or shell metacharacters" >&2
		exit 1
	fi
	
	# Resolve to absolute path
	if [[ "$bin" == /* ]]; then
		# Already absolute path
		resolved_bin="$bin"
	else
		# Find in PATH using command -v
		resolved_bin="$(command -v "$bin" 2>/dev/null)"
		if [ -z "$resolved_bin" ]; then
			echo "ERROR: Cannot find OpenSSL binary '$bin' in PATH" >&2
			echo "Please ensure OpenSSL is installed or set LITTLESECRETS_OPENSSL_BIN to the correct path" >&2
			exit 1
		fi
	fi
	
	# Verify it's a regular file (not a directory or special file)
	if [ ! -f "$resolved_bin" ]; then
		echo "ERROR: '$resolved_bin' is not a regular file" >&2
		exit 1
	fi
	
	# Verify it's executable
	if [ ! -x "$resolved_bin" ]; then
		echo "ERROR: '$resolved_bin' is not executable" >&2
		echo "Please check file permissions" >&2
		exit 1
	fi
	
	# Verify it's actually OpenSSL by checking version output
	# This prevents someone from substituting a malicious binary
	if ! "$resolved_bin" version 2>/dev/null | grep -qiE "openssl|libressl"; then
		echo "WARNING: '$resolved_bin' does not appear to be OpenSSL or LibreSSL" >&2
		echo "Output from '$resolved_bin version':" >&2
		"$resolved_bin" version 2>&1 | head -3 >&2
		echo "Proceeding anyway, but cryptographic operations may fail" >&2
	fi
	
	echo "$resolved_bin"
}
# Validate and make readonly to prevent mid-flight tampering
LITTLESECRETS_OPENSSL_BIN="$(ls_validate_openssl_bin "${LITTLESECRETS_OPENSSL_BIN:-openssl}")"
readonly LITTLESECRETS_OPENSSL_BIN
# --
# Options:
# - hmac: stores the secret HMAC for verification
LITTLESECRETS_OPTIONS=${LITTLESECRETS_OPTIONS:-hmac}

# -----------------------------------------------------------------------------
#
# COLORS
#
# -----------------------------------------------------------------------------

# --
# Color library
if [ -z "${NOCOLOR:-}" ] && [ -t 1 ] && [ -t 2 ] && [ -n "${TERM:-}" ] && tput setaf 1 &>/dev/null; then
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
else
	CYAN=""
	BLUE_DK=""
	BLUE=""
	BLUE_LT=""
	GREEN=""
	YELLOW=""
	GRAY=""
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

# -----------------------------------------------------------------------------
#
# LOGGING
#
# -----------------------------------------------------------------------------

LS_LOG_PREFIX="${DIM}[ls]${RESET}"
LS_LOG_FILTER="${LITTLESECRETS_LOG_FILTER:-warning}"

function ls_log {
	echo "${LS_LOG_PREFIX}$*${RESET}" >&2
}

function ls_log_external {
	if [[ "$LS_LOG_FILTER" = *"debug"* ]]; then
		cat >&2
	else
		cat >/dev/null
	fi
}

function ls_log_action {
	if [[ "$LS_LOG_FILTER" = *"action"* ]]; then
		ls_log "${DIM}${BOLD} → ACT $*"
	fi
	return 0
}

function ls_log_message {
	if [[ "$LS_LOG_FILTER" = *"message"* ]]; then
		ls_log "${DIM} … NFO $*"
	fi
	return 0
}

function ls_log_progress {
	if [[ "$LS_LOG_FILTER" = *"progress"* ]]; then
		ls_log "${DIM} … PRG $*"
	fi
	return 0
}

function ls_log_tip {
	if [[ "$LS_LOG_FILTER" = *"tip"* ]]; then
		ls_log " ✱ TIP $*"
	fi
	return 0
}

function ls_log_error {
	# NOTE: Errors are always logged
	ls_log "${RED} ! ERR ${BOLD}$*"
	return 0
}

function ls_log_warning {
	if [[ "$LS_LOG_FILTER" = *"warning"* ]]; then
		ls_log "${ORANGE} ⚠ WRN ${BOLD}$*"
	fi
	return 0
}

function ls_log_output_start {
	if [[ "$LS_LOG_FILTER" = *"output"* ]]; then
		echo -n "${GRAY}" >&2
	fi
}

function ls_log_output_end {
	if [[ "$LS_LOG_FILTER" = *"output"* ]]; then
		echo -n "${RESET}" >&2
	fi
}

function ls_log_stack {
	if [[ "$LS_LOG_FILTER" != *"debug"* ]]; then
		return 0
	fi
	local line=""
	local frame=""
	local func=""
	local path=""
	for ((i = ${1:-0}; i < ${#FUNCNAME[@]}; i++)); do
		frame="$(caller "$i")"
		if [ -n "$frame" ]; then
			line="$(echo "$frame" | cut -d' ' -f1)"
			func="$(echo "$frame" | cut -d' ' -f2)"
			path="$(echo "$frame" | cut -d' ' -f3-)"
			ls_log "${ORANGE} ▸  #${i} ${YELLOW}${BOLD}$func() ${RESET}$path:$line"
		fi
	done
}

function ls_on_error {
	echo >&2 "${LS_LOG_PREFIX}${RED} ⚠  ERR LittleSecrets Command failed $?: !! ${RESET}"
	ls_log_stack 5
	if [ -n "${LS_TRAP_ERROR_PREVIOUS}" ]; then
		eval "$LS_TRAP_ERROR_PREVIOUS"
	fi

	exit 1
}

# -----------------------------------------------------------------------------
#
# UTILS
#
# -----------------------------------------------------------------------------

# --
# Secure creation of a file that will be cleaned up, OK to store secrets
# and keys.
function ls_mkstemp {
	local res
	# Ensures we write in a directory not accessible to other users
	res="$(mktemp -p "${TMPDIR:-/tmp}")"
	chmod 600 "$res"
	LS_CLEANUP+=("$res")
	# If there's a second argument, that's going to be the contents, previously
	# encoded.
	if [ -n "${1:-}" ]; then
		printf '%s' "$1" | ls_decode >"$res"
	fi
	echo "$res"
}

# --
# - If PATH contains a path separator, resolve the path relative to the current directory
# - Otherwise find a matching link or path in all ancestors, returning the closes one
function ls_find {
	local search_path="$1"
	# If path contains separator, resolve relative to current dir
	if [[ "$search_path" == */* ]]; then
		if [ -e "$search_path" ]; then
			echo "$search_path"
			return 0
		fi
		return 1
	fi
	# Otherwise search up through ancestors
	local current_dir="$PWD"
	while true; do
		if [ -e "$current_dir/$search_path" ]; then
			echo "$current_dir/$search_path"
			return 0
		fi
		if [ "$current_dir" = "/" ]; then
			break
		fi
		current_dir="$(dirname "$current_dir")"
	done
	return 1
}

# --
# Finds all matching stores in the current directory and its ancestors.
function ls_find_all {
	local search_path="$1"
	if [[ "$search_path" == */* ]]; then
		if [ -e "$search_path" ]; then
			echo "$search_path"
			return 0
		fi
		return 1
	fi
	local current_dir="$PWD"
	while true; do
		if [ -e "$current_dir/$search_path" ]; then
			echo "$current_dir/$search_path"
		fi
		if [ "$current_dir" = "/" ]; then
			break
		fi
		current_dir="$(dirname "$current_dir")"
	done
}

function ls_mkparent {
	local path
	local parent
	for path in "$@"; do
		parent="$(dirname "$path")"
		if [ -z "$parent" ]; then
			parent=
		elif [ ! -e "$parent" ]; then
			mkdir -p "$parent"
		fi
	done
}

function ls_unlink {
	local path
	for path in "$@"; do
		if [ -z "$path" ]; then
			path=
		elif [ -e "$path" ]; then
			unlink "$path"
		fi
	done
}

# --
# Ensures that temporary files are cleaned up
function ls_cleanup {
	local path
	for path in "${LS_CLEANUP[@]}"; do
		if [ -z "$path" ]; then
			# nothing
			path=
		elif [ -e "$path" ]; then
			unlink "$path"
		fi
	done
	if [ -n "${LS_TRAP_EXIT_PREVIOUS:-}" ]; then
		eval "$LS_TRAP_EXIT_PREVIOUS"
	fi
}

function ls_validate_name { # NAME
	local name="${1:-}"
	if [ -z "$name" ]; then
		return 1
	fi
	if [[ "$name" == *"/"* ]] || [[ "$name" == *".."* ]]; then
		return 1
	fi
	if [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
		return 0
	else
		return 1
	fi
}

function ls_is_path { ## PATHLIKE
	local candidate="${1:-}"
	if [ -z "$candidate" ] || [[ "$candidate" == *$'\n'* ]] || [[ "$candidate" == *" "* ]] || [[ "$candidate" == @LS:* ]] || [[ "$candidate" == *"BEGIN "* ]]; then
		return 1
	fi
	if [[ "$candidate" == */* ]] || [ -e "$candidate" ]; then
		return 0
	else
		return 1
	fi
}

# --
# Echoes `TEXT` if any `EXPR` (glob) matches `TEXT`
function ls_match { # TEXT EXPR…
	local text="$1"
	local pattern
	shift # Remove first argument, leaving only the patterns
	if [ "$#" == 0 ]; then
		echo "$text"
		return 0
	else
		# FIXME: This does not seem to work with globs
		for pattern in "$@"; do
			# shellcheck disable=SC2053
			if [[ "$text" == $pattern ]]; then
				echo "$text"
				return 0
			fi
		done
		return 1
	fi
}

function ls_match_item {
	local store
	store="$(ls_store)"
	local item=
	local path="$1"
	shift
	if [ -n "$store" ]; then
		for item_path in ${store}/${path}; do
			if [ -e "$item_path" ]; then
				item="$(basename "$(dirname "$item_path")")"
				if [ -n "$(ls_match "$item" "$@")" ]; then
					echo "$item_path"
				fi
			fi
		done
	else
		return 1
	fi
}

# --
# Returns the option name if is defined
function ls_option { # OPTION
	if [[ $LITTLESECRETS_OPTIONS == *"$1"* ]]; then
		echo "$1"
	fi
}

# -----------------------------------------------------------------------------
#
# JSON UTILITIES
#
# -----------------------------------------------------------------------------

# Function: ls_json_escape [STRING]
# Escapes a string for JSON output
function ls_json_escape() {
	local str="${1:-}"
	# Escape backslashes first
	str="${str//\\/\\\\}"
	# Escape double quotes
	str="${str//\"/\\\"}"
	# Escape newlines, tabs, and other control characters
	str="${str//$'\n'/\\n}"
	str="${str//$'\r'/\\r}"
	str="${str//$'\t'/\\t}"
	# Escape other control characters (ASCII 0-31) using a more portable approach
	# Try different methods in order of preference
	if command -v awk >/dev/null 2>&1; then
		# Use awk with a more portable approach
		printf '%s' "$str" | awk '
		BEGIN {
			for (i = 0; i <= 31; i++) {
				if (i != 9 && i != 10 && i != 13) {  # Skip tab, newline, carriage return
					ctrl[sprintf("%c", i)] = sprintf("\\u00%02X", i)
				}
			}
		}
		{
			result = ""
			for (i = 1; i <= length($0); i++) {
				char = substr($0, i, 1)
				if (char in ctrl) {
					result = result ctrl[char]
				} else {
					result = result char
				}
			}
			printf "%s", result
		}
		' 2>/dev/null && return 0
	fi

	# Fallback: use a loop with printf for each character
	local result=""
	local i
	for ((i = 0; i < ${#str}; i++)); do
		local char="${str:$i:1}"
		local ascii_val
		ascii_val=$(printf '%d' "'$char" 2>/dev/null || echo 0)
		if ((ascii_val >= 0 && ascii_val <= 31)) && [[ "$char" != $'\n' && "$char" != $'\r' && "$char" != $'\t' ]]; then
			result+="\\u00$(printf '%02X' "$ascii_val")"
		else
			result+="$char"
		fi
	done
	printf '%s' "$result"
}

# Function: ls_json_string [STRING]
# Outputs a JSON string with proper escaping
function ls_json_string() {
	local str="${1:-}"
	printf '"%s"' "$(ls_json_escape "$str")"
}

# Function: ls_json_is_binary [STRING]
# (Deprecated internal heuristic) Kept for backwards compatibility.
# Returns 0 if STRING appears binary (control chars besides tab/newline/CR) otherwise 1.
function ls_json_is_binary() {
	local str="${1:-}"
	if [ -z "$str" ]; then
		return 1
	fi
	local count
	count="$(printf '%s' "$str" | tr -d '[:print:][:space:]' | tr -d '\200-\377' | wc -c)"
	if [ "$count" -gt 0 ]; then
		return 0
	fi
	return 1
}

# Function: ls_is_binary_file [PATH]
# Returns 0 if file contains bytes outside printable text range
# (control chars except \t,\n,\r or high-bit bytes), else 1.
function ls_is_binary_file() {
	local path="${1:-}"
	if [ -z "$path" ] || [ ! -f "$path" ]; then
		return 1
	fi
	# Empty file is text
	if [ ! -s "$path" ]; then
		return 1
	fi
	local count
	count="$(tr -d '[:print:][:space:]' <"$path" | tr -d '\200-\377' | wc -c)"
	if [ "$count" -gt 0 ]; then
		return 0
	fi
	return 1
}

# Function: ls_file_base64 [PATH]
# Emits base64 (no newlines) of file contents
function ls_file_base64() {
	local path="${1:-}"
	if [ -z "$path" ] || [ ! -f "$path" ]; then
		return 1
	fi
	"$LITTLESECRETS_OPENSSL_BIN" base64 -A <"$path"
}

# Emits a JSON array of non-empty string values.
function ls_json_emit_string_array { # INDENT ITEMS...
	local indent="$1"
	shift
	printf '%s[' "$indent"
	local first=true
	for item in "$@"; do
		if [ -n "$item" ]; then
			if [ "$first" = true ]; then
				first=false
			else
				printf ', '
			fi
			printf '%s' "$(ls_json_string "$item")"
		fi
	done
	printf ']'
}

# Function: ls_json_emit_key_array KEY [ITEM...]
# Emits a JSON key mapped to an array of string values (no trailing comma).
function ls_json_emit_key_array() { # KEY ITEMS...
	local key="$1"
	shift || true
	printf '  %s: ' "$(ls_json_string "$key")"
	ls_json_emit_string_array '' "$@"
}

# -----------------------------------------------------------------------------
#
# KEYS
#
# -----------------------------------------------------------------------------

# --
# Ensures that the `LITTLESECRETS_KEY` exists and is in the right format.
function ls_ssh_keypair_ensure { # KEYPATH
	local privkey_path="${1:-$LITTLESECRETS_KEY}"
	if [[ "$privkey_path" == *$'\n'* ]]; then
		ls_log_error "SSH private key path is invalid"
		return 1
	fi
	privkey_path="$(realpath -m -- "$privkey_path")"
	ls_mkparent "$privkey_path"
	local lock_path
	lock_path="${privkey_path}.littlesecrets.lock"
	local lock_fd
	# The source key and its derived files are shared by concurrent CLI processes.
	# Hold one per-source-key lock across their complete initialization.
	if ! exec {lock_fd}>"$lock_path"; then
		ls_log_error "Could not create SSH key lock: $lock_path"
		return 1
	fi
	if ! flock -x "$lock_fd"; then
		ls_log_error "Could not acquire SSH key lock: $lock_path"
		exec {lock_fd}>&-
		return 1
	fi
	# Ensures private key exists, otherwise creates it
	if [ ! -e "$privkey_path" ]; then
		ls_log_message "Missing SSH RSA key: $privkey_path"
		ls_log_action "Creating SSH key using 'ssh-keygen -t rsa -b 4096'"
		ls_log_output_start
		ssh-keygen -q -t rsa -b 4096 -N "" -f "$privkey_path" 2> >(ls_log_external)
		ls_log_output_end
	fi
	if ! ssh-keygen -y -P "" -f "$privkey_path" >/dev/null 2>&1; then
		ls_log_error "SSH private key with passphrase are not supported: $privkey_path"
		flock -u "$lock_fd"
		exec {lock_fd}>&-
		return 1
	fi
	local key_id
	key_id=$("$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 "$privkey_path" | cut -d' ' -f2 | cut -c1-16)
	local privkey_parent
	privkey_parent=$(dirname -- "$(realpath -- "$privkey_path")")
	local privkey_pem_path="${privkey_parent}/littlesecrets-${key_id}.pem"
	local pubkey_pem_path="${privkey_parent}/littlesecrets-${key_id}.pem.pub"
	# Ensures PEM private key exists, and is up to date
	if [ ! -e "$privkey_pem_path" ] || [ "$privkey_path" -nt "$privkey_pem_path" ]; then
		local privkey_ssh_tmp
		privkey_ssh_tmp="$(mktemp "${privkey_pem_path}.ssh.XXXXXX")"
		LS_CLEANUP+=("$privkey_ssh_tmp")
		local privkey_pem_tmp
		privkey_pem_tmp="$(mktemp "${privkey_pem_path}.tmp.XXXXXX")"
		LS_CLEANUP+=("$privkey_pem_tmp")
		ls_log_action "Converting SSH RSA DER key to PEM format: $privkey_pem_path"
		# NOTE: ssh-keygen will overwrite the key, so we copy it
		cp -a "$privkey_path" "$privkey_ssh_tmp"
		# SSH key is in DER format, we need PEM
		ls_log_output_start
		ssh-keygen -q -p -m pem -N '' -f "$privkey_ssh_tmp" 2> >(ls_log_external)
		"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$privkey_ssh_tmp" -out "$privkey_pem_tmp" 2> >(ls_log_external)
		ls_log_output_end
		chmod 400 "$privkey_pem_tmp"
		mv -f "$privkey_pem_tmp" "$privkey_pem_path"
		ls_unlink "$privkey_ssh_tmp"
	fi
	# Ensures PEM public key exists, and is up to date
	if [ ! -e "$pubkey_pem_path" ] || [ "$privkey_pem_path" -nt "$pubkey_pem_path" ]; then
		local pubkey_pem_tmp
		pubkey_pem_tmp="$(mktemp "${pubkey_pem_path}.tmp.XXXXXX")"
		LS_CLEANUP+=("$pubkey_pem_tmp")
		ls_log_action "Deriving PKCS8 public key from RSA PEM private key: $pubkey_pem_path"
		ls_log_output_start
		"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$privkey_pem_path" -pubout -out "$pubkey_pem_tmp" 2> >(ls_log_external)
		ls_log_output_end
		chmod 400 "$pubkey_pem_tmp"
		mv -f "$pubkey_pem_tmp" "$pubkey_pem_path"
	fi
	if [ ! -e "$privkey_pem_path" ] || [ ! -e "$pubkey_pem_path" ]; then
		ls_log_error "Could not create PEM keypair from SSH keypair: $privkey_path"
		flock -u "$lock_fd"
		exec {lock_fd}>&-
		return 1
	fi
	flock -u "$lock_fd"
	exec {lock_fd}>&-
	echo "${privkey_pem_path}"
}

# FIXME: These two functions are a bit dangerous, and don't really work
# in all cases that should be supported.
# --
# Returns the normalize private key path for the key at the given path
function ls_privkey_path { #KEYPATH?
	ls_ssh_keypair_ensure "$@"
}

# --
# Returns the normalized public key path for the key at the given path
function ls_pubkey_path { #KEYPATH
	echo "$(ls_ssh_keypair_ensure "$@").pub"
}

function ls_privkey_new { #KEYPATH
	ls_mkparent "${1:-}"
	if [ -n "${1:-}" ]; then
		"$LITTLESECRETS_OPENSSL_BIN" genrsa -out "$1" 4096
		chmod 400 "$1"
	else
		# When no path is provided, output to stdout directly
		"$LITTLESECRETS_OPENSSL_BIN" genrsa 4096
	fi
}

# NOTE: Disabling this as ls_ssh_keypair_ensure is better
# # NOTE: This is redundant with ls_ssh_keypair_ensure
# # --
# # Imports the private key at the given file, outputting the normalized key value.
# # Will always return the private key as a its contents, not as a file.
# function ls_privkey_import { # KEYPATH
# 	local keypath="${1:-$(ls_pubkey_path)}"
# 	local keyfmt=
# 	local keypath_tmp=
# 	local keyout_tmp=
# 	if ls_is_path "$1" && [ -e "$1" ]; then
# 		keyfmt="$(ls_key_format "$keypath")"
# 	else
# 		keypath_tmp="$(ls_mkstemp)"
# 		echo -n "$keypath" | ls_decode >"$keypath_tmp"
# 		keypath="$keypath_tmp"
# 		keyfmt="$(ls_key_format "$keypath")"
# 	fi
# 	local res=0
# 	case "$keyfmt" in
# 	# We obviously only support private keys here
# 	private:ssh*)
# 		keyout_tmp=$(ls_mkstemp)
# 		if ls_is_path "$keypath"; then
# 			cp -a "$keypath" "$keyout_tmp"
# 		else
# 			echo "$keypath" >"$keyout_tmp"
# 		fi
# 		ls_log_output_start
# 		ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" >&2
# 		ls_log_output_end
# 		openssl rsa -in "$keyout_tmp"
# 		unlink "$keyout_tmp"
# 		;;
# 	private:pkcs8*)
# 		# That's what we want
# 		cat "$keypath"
# 		;;
# 	*)
# 		ls_log_error "ls_privkey_import: Unsupported format $keyfmt"
# 		;;
# 	esac
# 	ls_unlink "$keypath_tmp" "$keyout_tmp"
# }

# --
# Imports the key at the given file, outputting the normalized key value.
function ls_pubkey_import { #KEYPATH
	local keypath="${1:-$(ls_pubkey_path)}"
	local keyfmt=
	local keypath_tmp=
	local keyout_tmp=
	if ls_is_path "$1" && [ -e "$1" ]; then
		keyfmt="$(ls_key_format "$keypath")"
	else
		keypath_tmp="$(ls_mkstemp)"
		echo -n "$keypath" | ls_decode >"$keypath_tmp"
		keypath="$keypath_tmp"
		keyfmt="$(ls_key_format "$keypath")"
	fi
	local res=0
	case "$keyfmt" in
	private:ssh*)
		keyout_tmp=$(ls_mkstemp)
		cp -a "$keypath" "${keyout_tmp}"
		ls_log_output_start
		if ! ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" 2> >(ls_log_external); then
			res=$?
		else
			"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$keyout_tmp" -pubout 2> >(ls_log_external)
			res=$?
		fi
		ls_log_output_end
		unlink "$keyout_tmp"
		;;
	private:pkcs8*)
		"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$keypath" -pubout 2> >(ls_log_external)
		res=$?
		;;
	public:ssh+rsa*)
		ssh-keygen -f "$keypath" -e -m PKCS8 2> >(ls_log_external)
		res=$?
		;;
	public:spki*)
		cat "$keypath"
		;;
	*)
		ls_log_error "ls_pubkey_import: Unsupported key format: $keyfmt"
		res=1
		;;
	esac
	ls_unlink "$keypath_tmp" "$keyout_tmp"
	return $res
}

function ls_key_cat {
	local key="${1:-}"
	if [ -e "$key" ]; then
		cat "$key"
	else
		echo -n "$key"
	fi
}

function ls_key_id_match { #TYPE FORMATS
	local text="$1"
	shift
	# For each type:format specification
	for spec in "$@"; do
		# Split into type and formats
		local type="${spec%%:*}"
		local formats="${spec#*:}"
		# Check if text starts with type:
		if [[ "$text" == "$type:"* ]]; then
			# Extract the format part from text (between first and second colon)
			local text_format="${text#*:}"
			text_format="${text_format%%:*}"
			# Check each required format
			local ifs="$IFS"
			IFS='+' read -ra required_formats <<<"$formats"
			for fmt in "${required_formats[@]}"; do
				if [[ "$text_format" != *"$fmt"* ]]; then
					IFS="$ifs"
					return 1
				fi
			done
			IFS="$ifs"
			return 0
		fi
	done
	return 1
}

# --
# Outputs the type/format of the key, in `:` separated form
# 1) Key type, `public` or `private` or `unknown`
# 2) Key format, `+` separated, like `pkcs8+rsa`
# 3) `valid` if the format was validated, otherwise nothing
function ls_key_format { ## KEY_OR_PATH?
	# Function to analyze a single file
	local file="${1:-}"
	local tmp_file=""
	if [ -z "$file" ]; then
		# If there's no file, we read from stding
		tmp_file="$(ls_mkstemp)"
		cat /dev/stdin >"$tmp_file"
		file="$tmp_file"
	elif ! ls_is_path "$file"; then
		# If the argument is not a file, we create a temp file with
		# the contents without stat-ing the filesystem with key material
		tmp_file="$(ls_mkstemp)"
		printf '%s' "$file" >"$tmp_file"
		file="$tmp_file"
	fi

	# Check for SSH public key format
	if grep -q "^ssh-" "$file" 2>/dev/null; then
		if grep -q "^ssh-rsa" "$file"; then
			echo -n "public:ssh+rsa"
		elif grep -q "^ssh-ed25519" "$file"; then
			echo -n "public:ssh+ed25519"
		else
			echo -n "public:ssh+unknown"
		fi
	# Check for PEM format
	elif grep -q "BEGIN" "$file" 2>/dev/null; then
		if grep -q "BEGIN RSA PRIVATE KEY" "$file"; then
			echo -n "private:rsa+pem+pkcs8"
		elif grep -q "BEGIN EC PRIVATE KEY" "$file"; then
			echo -n "private:ecdsa+pem+sec1"
		elif grep -q "BEGIN PRIVATE KEY" "$file"; then
			echo -n "private:pkcs8"
		elif grep -q "BEGIN PUBLIC KEY" "$file"; then
			echo -n "public:spki"
		elif grep -q "BEGIN OPENSSH PRIVATE KEY" "$file"; then
			echo -n "private:ssh+der"
		else
			echo -n "unknown:unknown"
		fi
	else
		echo -n "unknown:unknown"
	fi

	# Additional OpenSSL analysis
	if command -v "$LITTLESECRETS_OPENSSL_BIN" >/dev/null 2>&1; then
		if "$LITTLESECRETS_OPENSSL_BIN" rsa -in "$file" -noout 2>/dev/null; then
			echo ":valid=rsa"
		elif "$LITTLESECRETS_OPENSSL_BIN" ec -in "$file" -noout 2>/dev/null; then
			echo ":valid=ec"
		else
			echo ":"
		fi
	else
		echo ":"
	fi
	if [ -n "$tmp_file" ]; then
		unlink "$tmp_file"
	fi
}

# -----------------------------------------------------------------------------
#
# CRYPTO
#
# -----------------------------------------------------------------------------

function ls_is_encoded {
	case "$1" in
	@LS:*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Converts stdin binary data to hex string without newlines
function ls_bin2hex {
	if command -v xxd >/dev/null 2>&1; then
		xxd -p -c 256 | tr -d '\n'
	else
		od -An -tx1 -v | tr -d ' \t\n'
	fi
}

# Converts stdin hex string to binary data
function ls_hex2bin {
	if command -v xxd >/dev/null 2>&1; then
		xxd -r -p
	else
		awk '{
			for(i=1; i<=length($0); i+=2) {
				byte = substr($0, i, 2)
				if (length(byte) == 2) {
					printf "%c", strtonum("0x" byte)
				}
			}
		}'
	fi
}

# --
# Safely encodes binary data to be stored in a variable
function ls_encode {
	echo -n "@LS:"
	"$LITTLESECRETS_OPENSSL_BIN" base64 -A </dev/stdin
}

# --
# Decoding version of `ls_encode`.
function ls_decode {
	local prefix
	read -r -n4 prefix
	if [ "$prefix" == "@LS:" ]; then
		"$LITTLESECRETS_OPENSSL_BIN" base64 -d -A </dev/stdin
	else
		echo -n "$prefix"
		cat </dev/stdin
	fi
}

# --
# Generates a symmetric key usable for a secret. The key is encoded to be
# stored in a variable.
function ls_key {
	# RSA 4096bits -> 512bytes
	# PKCS requires 11bytes padding, OAEP 42bytes
	local ks=$((LITTLESECRETS_KEYSIZE / 8 - 42))
	"$LITTLESECRETS_OPENSSL_BIN" rand "${1:-$ks}" | ls_encode
}

# --
function ls_encrypt_sym { # KEY
	local key_path
	key_path=$(ls_mkstemp "$1")
	local output_path
	output_path=$(ls_mkstemp)
	local pass_path
	pass_path=$(ls_mkstemp)
	local openssl_res=0
	ls_log_output_start
	# Convert raw key into hex to avoid line/newline/null truncation in OpenSSL -pass fd:
	ls_bin2hex <"$key_path" >"$pass_path"
	# NOTE: The fd anonymises the key path.
	exec 3<"$pass_path"
	if ! "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out "$output_path" -pass fd:3 2> >(ls_log_external); then
		openssl_res=1
		ls_log_error "ls_encrypt_sym: Could not encrypt secret"
	else
		cat "$output_path"
	fi
	exec 3<&-
	ls_log_output_end
	ls_unlink "$key_path" "$output_path" "$pass_path"
	return "$openssl_res"
}

# Function: ls_hmac KEY PATH?
# Calculates an HMAC-SHA256 without passing key material in process arguments.
function ls_hmac {
	local key="${1:-}"
	local path="${2:-/dev/stdin}"
	key="${key//[[:space:]]/}" # Trim whitespace
	if [ -z "$key" ]; then
		ls_log_error "ls_hmac: Given key is empty"
		return 1
	fi
	local key_hex
	key_hex="$(printf '%s' "$key" | ls_bin2hex)"
	if [ "${#key_hex}" -gt 128 ]; then
		key_hex="$(printf '%s' "$key" | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex)"
	fi
	while [ "${#key_hex}" -lt 128 ]; do key_hex+="00"; done
	local inner_hex=""
	local outer_hex=""
	local offset
	local byte
	for ((offset = 0; offset < 128; offset += 2)); do
		byte=$((16#${key_hex:offset:2}))
		printf -v byte '%02x' "$((byte ^ 0x36))"
		inner_hex+="$byte"
		byte=$((16#${key_hex:offset:2}))
		printf -v byte '%02x' "$((byte ^ 0x5c))"
		outer_hex+="$byte"
	done
	local inner_digest
	if ! inner_digest=$({ printf '%s' "$inner_hex" | ls_hex2bin; cat "$path"; } | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex); then
		ls_log_error "ls_hmac: Could not generate secret HMAC"
		return 1
	fi
	if ! { printf '%s' "$outer_hex$inner_digest" | ls_hex2bin; } | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 | cut -d' ' -f2 | tr '[:lower:]' '[:upper:]'; then
		ls_log_error "ls_hmac: Could not generate secret HMAC"
		return 1
	fi
}

# --
# Decrypts `1:SECRET` (encoded) with `2:KEY` (encoded), returning the
# decrypted secrets (unencoded)
function ls_decrypt_sym { # KEY
	local res=0
	local key_path
	key_path=$(ls_mkstemp "$1")
	local input_path
	input_path=$(ls_mkstemp)
	local output_path
	output_path=$(ls_mkstemp)
	local pass_path
	pass_path=$(ls_mkstemp)
	# Read input first
	cat >"$input_path"
	ls_bin2hex <"$key_path" >"$pass_path"
	exec 3<"$pass_path"
	if ! "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -d -in "$input_path" -out "$output_path" -pass fd:3 2> >(ls_log_external); then
		res=1
		ls_log_error "ls_decrypt_sym: Could not symmetrically decrypt secret [$res]"
	else
		cat "$output_path"
	fi
	exec 3<&-
	ls_log_output_end
	ls_unlink "$key_path" "$input_path" "$output_path" "$pass_path"
	return "$res"
}

# --
# Encrypts the given secret using the given public key. When the key is empty
# it will be sourced using `ls_pubkey`, otherwise it can be given either
# as a path, or as a value. This returns the encrypted secret.
function ls_encrypt_asym { # PUBKEY? PATH?
	local pubkey="${1:-}"
	local secret_path="${2:-/dev/stdin}"
	local pubkey_path=
	local pubkey_temp=0
	local res=0
	if [ -z "$pubkey" ]; then
		pubkey_path="$(ls_pubkey_path)"
	elif [ -e "$pubkey" ]; then
		pubkey_path="$pubkey"
	else
		pubkey_path="$(ls_mkstemp "$pubkey")"
		pubkey_temp=1
	fi
	ls_log_output_start
	local output_path
	output_path=$(ls_mkstemp)
	if ! "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -encrypt -pubin -inkey "$pubkey_path" -in "${secret_path}" -out "$output_path" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2> >(ls_log_external); then
		res=1
		ls_log_error "ls_encrypt_asym: Could not asymmetrically encrypt secret"
	else
		cat "$output_path"
	fi
	ls_log_output_end
	unlink "$output_path"
	if [ "$pubkey_temp" == 1 ]; then
		unlink "$pubkey_path"
	fi
	return $res
}

# --
# Decrypts the given encrypted secret using the given private key. When the key is empty
# it will be sourced using `ls_privkey`, otherwise it can be given either
# as a path, or as a value. This returns the decypted secret.
function ls_decrypt_asym { # PRIVKEY? PATH?
	local privkey="${1:-}"
	local secret_path="${2:-/dev/stdin}"
	local privkey_path=
	local privkey_temp=0
	local res=0
	if [ -z "$privkey" ]; then
		privkey_path="$(ls_privkey_path)"
	elif [ -e "$privkey" ]; then
		privkey_path="$privkey"
	else
		privkey_path="$(ls_mkstemp "$privkey")"
		privkey_temp=1
	fi
	ls_log_output_start
	local output_path
	output_path=$(ls_mkstemp)
	if ! "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -decrypt -inkey "$privkey_path" -in "$secret_path" -out "$output_path" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2> >(ls_log_external); then
		ls_log_error "ls_decrypt_asym: Could not asymmetrically decrypt secret [$?]"
		res=1
	else
		cat "$output_path"
	fi
	ls_log_output_end
	unlink "$output_path"
	if [ "$privkey_temp" == 1 ]; then
		unlink "$privkey_path"
	fi
	return $res
}

# -----------------------------------------------------------------------------
#
# API
#
# -----------------------------------------------------------------------------

# =============================================================================
# STORE
# =============================================================================

# --
# Finds a matching store
function ls_store {
	ls_find "$LITTLESECRETS_STORE"
}

function ls_store_list {
	ls_find_all "$LITTLESECRETS_STORE"
}

function ls_store_init {
	local parent="${1:-.}"
	if [ ! -e "$parent/$LITTLESECRETS_STORE_NAME" ]; then
		mkdir -p "$parent/$LITTLESECRETS_STORE_NAME"
	fi
	realpath "$parent/$LITTLESECRETS_STORE_NAME"
}

# --
# Ensures that the store exists
function ls_store_ensure {
	local store
	store=$(ls_store)
	if [ -z "$store" ]; then
		store="$(basename "$LITTLESECRETS_STORE")"
		mkdir -p "$store"
	fi
	echo "$store"
}

# =============================================================================
# USERS
# =============================================================================

# --
# Lists all the users in the store
function ls_user_list { # EXPR…
	ls_match_item "user/*/*.pubkey" "$@" | rev | cut -d/ -f1,2 | rev | sed 's|.pubkey||g;s|/|:|g' | sort
}

function ls_user_registration_path { # USER? KEY?
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user
	user="$(ls_user_name "${1:-}")"
	local host
	host="$(ls_user_host "${1:-}" "${2:-}")"
	if ! ls_validate_name "$user" || ! ls_validate_name "$host"; then return 1; fi
	local keypath="$store/user/$user/$host.pubkey"
	if [ -e "$keypath" ]; then
		echo "$keypath"
		return 0
	else
		return 1
	fi
}

# --
# Registers user with the given $(KEY)
function ls_user_register { # USER? KEY?
	local store
	store="$(ls_store_ensure)"
	local user
	user="$(ls_user_name "${1:-}")"
	local host
	host="$(ls_user_host "${1:-}" "${2:-$LITTLESECRETS_KEY}")"
	if ! ls_validate_name "$user"; then
		ls_log_error "ls_user_register: Invalid user name: $user"
		return 1
	fi
	if ! ls_validate_name "$host"; then
		ls_log_error "ls_user_register: Invalid host name: $host"
		return 1
	fi
	local key
	key="$(ls_pubkey_import "${2:-$LITTLESECRETS_KEY}")"
	ls_log_action "Registering user '$user' on '$host' from key '${2:-$LITTLESECRETS_KEY}'"

	local user_key_path="$store/user/$user/$host.pubkey"
	if [ -z "$key" ]; then
		ls_log_error "Could not import user public key: $(ls_pubkey_path "${1:-}" "${2:-}")"
		return 1
	fi
	if [ -e "$user_key_path" ]; then
		if ! cmp -s "$user_key_path" <(echo "$key"); then
			# We're overriding an existing key
			ls_log_warning "SECURITY WARNING: Overwriting existing public key for '$user@$host'; previously encrypted secrets will become inaccessible to this key."
			echo "$key" >"$user_key_path"
		fi
	else
		# That's a new key
		mkdir -p "$(dirname "$user_key_path")"
		echo "$key" >"$user_key_path"
	fi
	echo "$user_key_path"
	return 0
}

function ls_user_list_keys { # USER? HOST?
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user
	user="$(ls_user_name "${1:-}")"
	if ! ls_validate_name "$user"; then return 1; fi
	local host="${2:-}"
	if [ -n "$host" ]; then
		if ! ls_validate_name "$host"; then return 1; fi
		# If host is specified, only return that specific key
		local keypath="$store/user/$user/$host.pubkey"
		if [ -e "$keypath" ]; then
			echo "$keypath"
		fi
	else
		# Otherwise return all host keys for the user
		for keypath in "$store/user/$user"/*.pubkey; do
			if [ -e "$keypath" ]; then
				echo "$keypath"
			fi
		done
	fi
}

# Lists registered public-key paths matching USER or USER@HOST glob expressions.
function ls_user_key_paths { # USER_EXPR...
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user_expr
	local registered_user
	local user
	local host
	local key_path
	for user_expr in "$@"; do
		for registered_user in $(ls_user_list); do
			user="${registered_user%%:*}"
			host="${registered_user#*:}"
			if [[ "$user_expr" == *@* ]]; then
				ls_match "$user@$host" "$user_expr" >/dev/null || continue
			else
				ls_match "$user" "$user_expr" >/dev/null || continue
			fi
			key_path="$store/user/$user/$host.pubkey"
			if [ -e "$key_path" ]; then
				echo "$key_path"
			fi
		done
	done | sort -u
}

# --
# Tries to extract the user@host from the given key.
function ls_pubkey_meta { # KEY
	local key="${1:-}"
	local fmt
	fmt="$(ls_key_format "$key")"
	case "$fmt" in
	public:ssh*)
		ls_key_cat "$key" | rev | cut -d' ' -f1 | rev
		;;
	*) ;;
	esac
}

function ls_user_name { # USER? KEY?
	local user="${1:-$LITTLESECRETS_USER}"
	local key="${2:-}"
	if [ -n "$key" ]; then
		local meta
		meta="$(ls_pubkey_meta "$key")"
		if [ -n "$meta" ]; then
			ls_user_name "$meta"
			return 0
		fi
	fi
	# Extract username if in user@host format
	echo "${user%@*}"
}

function ls_user_host { # USER? KEY?
	local user="${1:-$LITTLESECRETS_USER}"
	local key="${2:-}"
	if [ -n "$key" ]; then
		local meta
		meta="$(ls_pubkey_meta "$key")"
		if [ -n "$meta" ]; then
			ls_user_host "$meta"
			return 0
		fi
	fi
	if [[ "$user" == *@* ]]; then
		# Extract hostname from user@host
		echo "${user#*@}"
	else
		# Use default host
		echo "$LITTLESECRETS_HOST"
	fi
}

# --
# Returns the public key for the given KEY (if present), otherwise
# retrieves the public key for the given user (registered). The
# key may be returned as a path, or as a data.
function ls_user_pubkey { # USER? KEY?
	if [ -n "${2:-}" ]; then
		# If a KEY is given, the we try to get a pubkey from it
		ls_pubkey_import "${2:-$LITTLESECRETS_KEY}"
	else
		# If not KEY is given, we look for a user.
		local user
		user="$(ls_user_name "${1:-}")"
		local host
		host="$(ls_user_host "${1:-}")"
		local store
		store="$(ls_store)"
		if [ -n "$store" ]; then
			# If there's a store and the userkey exist, we return it.
			local keypath
			keypath="$(ls_store)/user/$user/$host.pubkey"
			if [ -e "$keypath" ]; then
				echo "$keypath"
				return 0
			else
				return 1
			fi
		fi
	fi
}

# --
# Returns the private key (as content) for the current user. This will
# retrieve the private key from the `LITTLESECRETS_KEY`, or use the
# given `KEY` if provided.
function ls_user_privkey { # KEY?
	if [ -z "${1:-}" ]; then
		local privkey_path
		privkey_path=$(ls_privkey_path "${1:-$LITTLESECRETS_KEY}")
		if [ -e "$privkey_path" ]; then
			cat "$privkey_path"
		else
			ls_log_error "ls_user_privkey: Could not find private key at: ${1:-$LITTLESECRETS_KEY}"
			return 1
		fi
	else
		local key="$1"
		local key_fmt
		key_fmt=$(ls_key_format "$key")
		if [[ "$key_fmt" == private:*pkcs8* ]]; then
			# The given keypath is already in the right format
			echo "$key"
		else
			ls_log_error "ls_user_privkey: Given key is not in PKCS8 format"
			# if [ -e "$keypath" ]; then
			# 	ls_log_action "ls_user_privkey: Importing private key to PKCS8/PEM format at $keypath"
			# else
			# 	ls_log_action "ls_user_privkey: Importing private key to PKCS8/PEM format"
			# fi
			# ls_privkey_import "$keypath"
			return 1
		fi
	fi
}

# =============================================================================
# SECRETS
# =============================================================================

function ls_secret_list {
	local secrets
	local secret
	secrets=$(ls_match_item "secret/*/secret.enc" "$@")
	if [ -z "$secrets" ]; then
		if [ -z "$*" ]; then
			ls_log_message "No secrets found at: $(ls_store)"
		else
			ls_log_message "No secrets matching '$*' found at: $(ls_store)"
		fi
	else
		local path
		local name
		local keys
		for secret in $secrets; do
			path="$(dirname "$secret")"
			name="$(basename "$path")"
			keys=$(ls "$path"/*.key 2>/dev/null)
			if [ -n "$keys" ]; then
				echo "$name"
			else
				ls_log_warning "Empty secrets folder: $path"
			fi
		done
	fi
}

function ls_secret_keys { # SECRET
	local path
	path="$(ls_secret_path "$1")"
	local keys
	keys=$(ls "$path"/*.key 2>/dev/null)
	if [ -n "$keys" ]; then
		echo "$keys" | xargs -n1 basename | sed "s|.key||g" | xargs echo -n
	fi
}

# Function: ls_try_write TMP DST ACTION
# Runs `ACTION` (which must return true) and is expected to
# write to `TMP`. If the action succeeds, then `TMP` is moved
# to `DST`, otherwise `TMP` is cleaned up.
function ls_try_write {
	local path_tmp="$1"
	local path_dst="$2"
	shift 2
	if ! "$@"; then
		ls_log_error "ls_try_write: Action failed, did not update: $path_dst"
		unlink "$path_tmp"
		return 1
	else
		if [ -e "$path_dst" ]; then
			ls_log_message "Updating: $path_dst"
		else
			ls_log_message "Creating: $path_dst"
		fi
		cat "$path_tmp" >"$path_dst"
		chmod 600 "$path_dst"
		unlink "$path_tmp"
		return 0
	fi
}

# TODO: PUBKEY should be user, maybe?
#
# Function: ls_secret_wite SECRET_NAME PUBKEY? SECRET_KEY
# Writes the secret with the `SECRET_NAME` using the `PUBKEY` and the given
# `SECRET_KEY`. The user will be inferred from the `PUBKEY`, the secret
# will be created in the storage, along with its hmac signature if not
# already there.
function ls_secret_write { # NAME PUBKEY? SECRETKEY?
	local secret_name="$1"
	if ! ls_validate_name "$secret_name"; then
		ls_log_error "ls_secret_write: Invalid secret name: $secret_name"
		return 1
	fi
	local secret_path
	secret_path="$(ls_store)/secret/$secret_name/secret.enc"
	local secret_hmac_path
	secret_hmac_path="$(ls_store)/secret/$secret_name/secret.hmac"
	local has_hmac
	has_hmac="$(ls_option hmac)"
	# This creates the secret key, if it is not given.
	# NOTE that the key is encoded with ls_encode.
	local secret_key="${3:-}"
	if [ -z "$secret_key" ]; then
		secret_key="$(ls_key)"
	fi
	# Capture plaintext secret from stdin into memory (avoids temp file exposure)
	local secret_plain
	secret_plain="$(cat /dev/stdin)"
	# Encrypt the secret using the symmetric key
	ls_log_action "ls_secret_write: Writing encrypted secret to $secret_path"
	ls_mkparent "$secret_path"
	local secret_path_tmp
	secret_path_tmp=$(ls_mkstemp)
	if ! printf '%s' "$secret_plain" | ls_encrypt_sym "$secret_key" >"$secret_path_tmp"; then
		ls_log_error "ls_secret_write: symmetric encryption failed at $secret_path"
		ls_unlink "$secret_path_tmp"
		unset secret_plain
		return 1
	fi
	# Atomically write encrypted secret
	ls_try_write "$secret_path_tmp" "$secret_path" true

	# Second step, encrypt the secret key for each of the user's host keys
	local res=0
	local user
	user=$(ls_user_name "" "${2:-}")
	local host
	local secret_key_path
	local secret_key_path_tmp
	if [ -n "${2:-}" ]; then
		# If a specific pubkey is provided, use only that
		local user_pubkey
		user_pubkey=$(echo "${2:-}" | ls_decode)
		host=$(ls_user_host "" "$2")
		secret_key_path="$(ls_store)/secret/$secret_name/$user@$host.key"
		secret_key_path_tmp=$(ls_mkstemp)
		ls_log_action "ls_secret_write: Encrypting secret key to $secret_key_path"
		# shellcheck disable=SC2094
		if ! ls_try_write "$secret_key_path_tmp" "$secret_key_path" ls_encrypt_asym "$user_pubkey" <(echo "$secret_key") >"$secret_key_path_tmp"; then
			ls_log_error "ls_secret_write: asymmetric encryption failed at $secret_key_path"
			unset secret_plain
			return 1
		fi
	else
		local user_keys
		user_keys=$(ls_user_list_keys "$user")
		if [ -z "$user_keys" ]; then
			ls_user_register
			user_keys=$(ls_user_list_keys "$user")
		fi
		if [ -z "$user_keys" ]; then
			ls_log_error "ls_secret_write: No user key found for $user"
			unset secret_plain
			return 1
		fi
		# Otherwise encrypt for all host keys
		for pubkey_path in $user_keys; do
			host=$(basename "$pubkey_path" .pubkey)
			secret_key_path="$(ls_store)/secret/$secret_name/$user@$host.key"
			secret_key_path_tmp=$(ls_mkstemp)
			ls_log_action "ls_secret_write: Encrypting secret key to $secret_key_path"
			# shellcheck disable=SC2094
			if ! ls_try_write "$secret_key_path_tmp" "$secret_key_path" ls_encrypt_asym "$pubkey_path" <(echo "$secret_key") >"$secret_key_path_tmp"; then
				ls_log_error "ls_secret_write: asymmetric encryption failed at $secret_key_path"
				res=1
			fi
		done
	fi
	# If the HMAC option is enabled, we create/update the HMAC
	if [ -n "$has_hmac" ]; then
		local hmac
		if ! hmac=$(printf '%s' "$secret_plain" | ls_secret_hmac - "$secret_key"); then
			ls_log_error "ls_secret_write: Could not compute HMAC for secret: $secret_name"
			unset secret_plain
			return 1
		elif [ ! -e "$secret_hmac_path" ]; then
			ls_log_action "Creating secret HMAC at: $secret_hmac_path"
			echo -n "$hmac" >"$secret_hmac_path"
		elif [ "$(cat "$secret_hmac_path")" != "$hmac" ]; then
			ls_log_action "Updating secret HMAC at: $secret_hmac_path"
			echo -n "$hmac" >"$secret_hmac_path"
		fi
	fi
	unset secret_plain
	echo "$secret_path"
	return $res
}

function ls_secret_add { # NAME VALUE PUBKEY? ENCKEY?
	if [ -n "${2:-}" ]; then
		echo -n "$2" | ls_secret_write "$1" "${3:-}" "${4:-}"
	else
		ls_secret_write "$1" "${3:-}" "${4:-}" </dev/stdin
	fi
}

function ls_secret_key_path { # SECRET USER[@HOST]?
	local store
	store="$(ls_store)"
	if [ -z "$store" ] || ! ls_validate_name "$1"; then return 1; fi
	local user
	user=$(ls_user_name "${2:-}")
	local host
	host=$(ls_user_host "${2:-}")
	if ! ls_validate_name "$user" || ! ls_validate_name "$host"; then return 1; fi
	local secret_key_path="$store/secret/$1/$user@$host.key"
	if [ -e "$secret_key_path" ]; then
		echo "$secret_key_path"
	else
		ls_log_warning "ls_secret_key_path: Secret key not defined: user=$user, host=$host, secret=$1"
	fi
}

function ls_secret_path { # SECRET
	# We locate the secret
	local secret="$1"
	if ! ls_validate_name "$secret"; then return 1; fi
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret_path="$store/secret/$secret"
	if [ ! -e "$secret_path/secret.enc" ]; then
		return 1
	else
		echo "$secret_path"
	fi
}

# --
# Looks for the secret key for the given secret, decrypting it with the given
# private key.
function ls_secret_key { # SECRET PRIVKEY?
	local user_privkey
	user_privkey=$(ls_user_privkey "${2:-}" | ls_decode)
	local secret_key_path
	if ! secret_key_path="$(ls_secret_key_path "$1")"; then
		return 1
	elif [ -z "$secret_key_path" ]; then
		ls_log_error "ls_secret_key: Could not retrieve path for secret key $1"
		return 1
	else
		ls_decrypt_asym "$user_privkey" <"$secret_key_path"
	fi
}

# Function: ls_secret_hmac_key ENC_KEY?
# Transforms the given key into a HMAC-able key, calculating its SHA256
# hash, and returning it as encoded to preserve entropy. The key value is either
# passed as argument, or read from stding.
function ls_secret_hmac_key {
	# NOTE: Any change in this format will then impact the HMAC signature
	if [ -z "${1:-}" ]; then
		ls_decode </dev/stdin | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex
	else
		printf '%s' "$1" | ls_decode | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex
	fi
}

# Function: ls_secret_hmac
# Calculates the HMAC for the given secret. If secret name is `-` then
# the secret is read from stdin.
function ls_secret_hmac { # SECRET_NAME SECRET_ENC_KEY?
	local secret_name="$1"
	local secret_key="${2:-}"
	# If the secret key is not provided, we try to retrieve it -- note that
	# this used the current USER/HOST.
	if [ -z "$secret_key" ]; then
		if ! secret_key="$(ls_secret_key "$1")"; then
			ls_log_error "ls_secret_hmac: Could not access secret key"
			return 1
		fi
	fi
	# The ls_secret_hmac_key will derive a key from the secret
	if [ "$secret_name" == "-" ]; then
		cat /dev/stdin | ls_hmac "$(ls_secret_hmac_key "$secret_key")"
	else
		ls_secret_get "$1" | ls_hmac "$(ls_secret_hmac_key "$secret_key")"
	fi
	return 0
}

function ls_secret_hmac_path { #SECRET
	echo "$(ls_secret_path "$1")/secret.hmac"
}

# Emits the JSON fields for a secret name/value pair.
function ls_json_emit_secret_value { # NAME VALUE INDENT?
	local name="$1"
	local value="$2"
	local indent="${3:-}"
	local tmp
	tmp="$(ls_mkstemp)"
	printf '%s' "$value" >"$tmp"
	local force_enc="${LITTLESECRETS_FORCE_ENCODING:-}"
	local is_binary=1
	if [ "$force_enc" = "base64" ]; then
		is_binary=0
	elif [ "$force_enc" = "text" ]; then
		is_binary=1
	elif ls_is_binary_file "$tmp"; then
		is_binary=0
	fi
	printf '%s"name": %s,\n' "$indent" "$(ls_json_string "$name")"
	if [ "$is_binary" -eq 0 ]; then
		local encoded_value
		encoded_value="$(ls_file_base64 "$tmp")"
		printf '%s"value": %s,\n' "$indent" "$(ls_json_string "$encoded_value")"
		printf '%s"encoding": "base64"' "$indent"
	else
		printf '%s"value": %s' "$indent" "$(ls_json_string "$value")"
	fi
	unlink "$tmp"
}

# Emits JSON for a secret name/value pair. Handles binary detection & base64.
function ls_secret_emit_json { # NAME VALUE
	printf '{\n'
	ls_json_emit_secret_value "$1" "$2" '  '
	printf '\n}\n'
}

function ls_secret_ensure { # NAME
	if [ -z "${1:-}" ]; then
		ls_log_error "ensure: Missing secret name"
		return 1
	fi
	if ! ls_validate_name "$1"; then
		ls_log_error "ensure: Invalid secret name: $1"
		return 1
	fi
	# Check if secret already exists (check the path, not access)
	if ls_secret_path "$1" >/dev/null 2>&1; then
		# Secret exists, check if user has access by trying to get the secret
		# We get the secret and output it, similar to the 'get' command
		local secret_value
		if ! secret_value=$(ls_secret_get "$1"); then
			ls_log_error "ensure: Secret '$1' exists but you don't have access to it"
			return 1
		fi
		# Secret exists and user has access, output the value in the requested format
		if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
			ls_secret_emit_json "$1" "$secret_value"
		else
			# Default text output format
			echo -n "$secret_value"
		fi
		return 0
	else
		# Secret doesn't exist, create a new random secret (16 ASCII chars)
		ls_log_action "ensure: Creating new random secret: $1"
		local random_secret
		# Generate 16 random ASCII characters (alphanumeric)
		# Use more base64 data to ensure we get 16 chars after filtering
		random_secret=$("$LITTLESECRETS_OPENSSL_BIN" rand -base64 20 | tr -d '=+/' | tr -d '\\n' | cut -c1-16)
		if [ -z "$random_secret" ]; then
			ls_log_error "ensure: Failed to generate random secret"
			return 1
		fi
		if ls_secret_add "$1" "$random_secret" >/dev/null; then
			# Output the newly created secret in the requested format
			if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
				ls_secret_emit_json "$1" "$random_secret"
			else
				# Default text output format
				echo -n "$random_secret"
			fi
			return 0
		else
			return $?
		fi
	fi
}

function ls_secret_get { # NAME PRIVKEY?
	# We locate the secret
	local secret="$1"
	if ! ls_validate_name "$secret"; then
		ls_log_error "ls_secret_get: Invalid secret name: $secret"
		return 1
	fi
	local store
	store="$(ls_store)"
	local secret_path="$store/secret/$secret/secret.enc"
	if [ ! -e "$secret_path" ]; then return 0; fi

	# First step, we decrypt the secret key with the user's private key
	local user
	user=$(ls_user_name)
	local host
	host=$(ls_user_host)
	local user_privkey
	user_privkey=$(ls_user_privkey "${2:-}" | ls_decode)
	local secret_key_path="$store/secret/$secret/$user@$host.key"
	if [ ! -e "$secret_key_path" ]; then
		ls_log_warning "ls_secret_get: Could not retrieve secret '$1', missing secret key path: $secret_key_path"
		return 1
	fi
	local secret_key
	if ! secret_key=$(ls_decrypt_asym "$user_privkey" <"$secret_key_path"); then
		ls_log_error "ls_secret_get: Could not retrieve secret '$1', secret key retrieval error: $secret_key_path"
		return 1
	fi
	if [ -z "$secret_key" ]; then
		ls_log_error "ls_secret_get: Could not retrieve secret '$1', decrypted secret key is empty: $secret_key_path"
		return 1
	fi
	# Second step, we decrypt the secret with
	local secret_val
	if secret_val="$(ls_decrypt_sym "$secret_key" <"$secret_path")"; then
		local secret_hmac_path="$store/secret/$secret/secret.hmac"
		if [ -e "$secret_hmac_path" ]; then
			local calculated_hmac
			if ! calculated_hmac="$(printf '%s' "$secret_val" | ls_secret_hmac - "$secret_key")"; then
				ls_log_error "ls_secret_get: Could not compute HMAC for secret: $secret"
				return 1
			elif ! cmp -s <(echo -n "$calculated_hmac") "$secret_hmac_path"; then
				ls_log_error "ls_secret_get: Secret HMAC validation failed for: $secret"
				return 1
			fi
		elif [ -n "$(ls_option hmac)" ]; then
			ls_log_warning "ls_secret_get: Missing secret HMAC: $secret_hmac_path"
			return 1
		fi
		echo -n "$secret_val"
		return 0
	else
		ls_log_error "ls_secret_get: Could not retrieve secret '$1', secret decryption error: $secret_path"
		return 1
	fi
}

# Function: ls_secret_verify
# Verifies that the secret `NAME` decrypted using the `PRIVKEY` has a
# matching HMAC with the one stored.
function ls_secret_verify { # NAME PRIVEY?
	local store
	store="$(ls_store)"
	local secret_hmac_path="$store/secret/$1/secret.hmac"
	# A missing HMAC is not a successful verification.
	if [ -n "$(ls_option hmac)" ] && [ ! -e "$secret_hmac_path" ]; then
		ls_log_warning "No hmac found for secret $1: $secret_hmac_path"
		return 1
	fi
	local hmac
	if ! hmac="$(ls_secret_hmac "$1" "$(ls_secret_key "$1" "${2:-}")")"; then
		ls_log_error "Verify could not compute HMAC for secret $1"
		return 1
	elif ! cmp -s <(echo -n "$hmac") "$secret_hmac_path"; then
		return 1
	else
		return 0
	fi
}

# Function: ls_secret_remove SECRET
# Removes *all* the files associated with the given secret, and clears the
# directory.
function ls_secret_remove {
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret="$1"
	if ! ls_validate_name "$secret"; then
		ls_log_error "ls_secret_remove: Invalid secret name: $secret"
		return 1
	fi
	local secret_path="$store/secret/$secret"
	if [ -e "$secret_path" ]; then
		ls_log_action "Removing secret files: $(env -C "$secret_path" find . -name "*.*")"
		rm -rf "$secret_path"
	fi
}

function ls_secret_grant { # SECRET USER_EXPR
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret_pattern="$1"
	shift

	# Get list of matching secrets
	local matching_secrets=()

	for s in $(ls_secret_list "$secret_pattern"); do
		matching_secrets+=("$s")
	done

	if [ ${#matching_secrets[@]} -eq 0 ]; then
		ls_log_warning "No secrets match pattern: $secret_pattern"
		return 1
	fi

	local recipient_keys
	recipient_keys="$(ls_user_key_paths "$@")"
	if [ -z "$recipient_keys" ]; then
		ls_log_error "User not found: $1"
		return 1
	fi

	# Process each matching secret
	for secret in "${matching_secrets[@]}"; do
		local secret_key
		if ! secret_key=$(ls_secret_key "$secret"); then
			ls_log_warning "Could not retrieve key for secret: $secret"
			continue
		fi

		ls_log_message "Granting access to secret: $secret"

		for pubkey_path in $recipient_keys; do
			local recipient_user
			local recipient_host
			recipient_user=$(basename "$(dirname "$pubkey_path")")
			recipient_host=$(basename "$pubkey_path" .pubkey)
			local secret_key_path="$store/secret/$secret/$recipient_user@$recipient_host.key"
			local secret_key_tmp
			secret_key_tmp=$(mktemp "${secret_key_path}.tmp.XXXXXX")
			LS_CLEANUP+=("$secret_key_tmp")
			local new_grant=0
			if [ ! -e "$secret_key_path" ]; then
				new_grant=1
			fi
			if ! ls_encrypt_asym "$pubkey_path" <(echo "$secret_key") >"$secret_key_tmp"; then
				ls_unlink "$secret_key_tmp"
				return 1
			fi
			mv -f "$secret_key_tmp" "$secret_key_path"
			if [ "$new_grant" = 1 ]; then
				ls_log_action "Granted access to secret '$secret' for '$recipient_user@$recipient_host'"
			fi
		done
	done
}

function ls_secret_users { # SECRET?
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi

	# If no secret specified, list for all secrets
	if [ -z "${1:-}" ]; then
		for secret in $(ls_secret_list); do
			echo -n "$secret:"
			ls_secret_users "$secret"
			echo
		done
		return 0
	fi

	# For a specific secret, list all users with access
	local users=""
	for keyfile in "$store/secret/$1"/*.key; do
		if [ -e "$keyfile" ]; then
			users="$users $(basename "$keyfile" .key)"
		fi
	done
	echo "${users# }"
}

function ls_secret_revoke { # SECRET USER_EXPR
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret="$1"
	if ! ls_validate_name "$secret"; then
		ls_log_error "ls_secret_revoke: Invalid secret name: $secret"
		return 1
	fi
	shift
	ls_log_tip "Revocation removes user key access. Rotate secret if previously accessed keys must be invalidated."
	local pubkey_path
	local user
	local host
	local secret_key_path
	for pubkey_path in $(ls_user_key_paths "$@"); do
		user="$(basename "$(dirname "$pubkey_path")")"
		host="$(basename "$pubkey_path" .pubkey)"
		secret_key_path="$store/secret/$secret/$user@$host.key"
		if [ -e "$secret_key_path" ]; then
			rm -f "$secret_key_path"
		fi
	done
}

function ls_user_deregister { # USER KEY?
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user_input="$1"
	local key="${2:-}"
	local user
	user="$(ls_user_name "$user_input")"
	local host
	host="$(ls_user_host "$user_input")"
	if ! ls_validate_name "$user"; then
		ls_log_error "ls_user_deregister: Invalid user name: $user"
		return 1
	fi
	if [[ "$user_input" == *@* ]] && ! ls_validate_name "$host"; then
		ls_log_error "ls_user_deregister: Invalid host name: $host"
		return 1
	fi
	local key_path
	local key_paths=()
	if [[ "$user_input" == *@* ]]; then
		key_paths=("$store/user/$user/$host.pubkey")
	else
		for key_path in "$store/user/$user"/*.pubkey; do
			if [ -e "$key_path" ]; then
				key_paths+=("$key_path")
			fi
		done
	fi
	if [ -n "$key" ]; then
		local given
		given=$(ls_pubkey_import "$key")
		for key_path in "${key_paths[@]}"; do
			if [ -e "$key_path" ] && cmp -s "$key_path" <(printf '%s\n' "$given"); then
				rm -f "$key_path"
				return 0
			fi
		done
		return 1
	fi
	if [ "${#key_paths[@]}" -eq 0 ]; then return 1; fi
	rm -f "${key_paths[@]}"
}

function ls_secret_export {
	# This exports as a shell script, but we could export to other formats if
	# necessary.
	if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
		# JSON output format: array of {"name": "secret.name", "value": "secret.value"}
		echo "["
		local first=true
		if [ $# -eq 0 ]; then
			# No arguments, export all secrets
			local secrets
			secrets=$(ls_secret_list)
			if [ -n "$secrets" ]; then
				for secret in $secrets; do
					if [ "$first" = true ]; then
						first=false
					else
						echo ","
					fi
					ls_secret_export_json_object "$secret"
				done
			fi
		else
			# Export specific secrets
			for var in "$@"; do
				local secname="${var##*=}"
				if [ "$first" = true ]; then
					first=false
				else
					echo ","
				fi
				ls_secret_export_json_object "$secname"
			done
		fi
		echo ""
		echo "]"
	else
		# Default shell script output format
		if [ $# -eq 0 ]; then
			local -a secrets=()
			while IFS= read -r s; do
				[ -n "$s" ] && secrets+=("$s")
			done < <(ls_secret_list)
			if [ ${#secrets[@]} -eq 0 ]; then
				echo "# No secrets in $(ls_store)"
			else
				ls_secret_export "${secrets[@]}"
			fi
		else
			local envname
			local secname
			local secval
			for var in "$@"; do
				envname="${var%%=*}"
				secname="${var##*=}"
				if [ "$envname" == "$secname" ]; then
					envname="$(echo "${envname//[.-]/_}" | tr '[:lower:]' '[:upper:]')"
				fi

				if [[ ! "$envname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
					ls_log_error "export: Invalid environment variable name: $envname"
					return 1
				fi

				if ! ls_secret_verify "$secname"; then
					ls_log_error "Could not validate secret authentiticy: $secname"
					echo "export $envname= # ERROR: Secret HMAC invalid"
				elif ! secval=$(ls_secret_get "$secname"); then
					ls_log_error "Unable to retrieve secret: $secname"
					echo "# Unable to retrieve secret: $secname"
				else
					# Safely escape single quotes for shell evaluation
					local escaped_val="${secval//\'/\'\\\'\'}"
					echo "export $envname='${escaped_val}'"
				fi
			done
		fi
	fi
}

# Function: ls_secret_export_json_object [SECRET_NAME]
# Helper function to output a single secret as JSON object for export
function ls_secret_export_json_object {
	local secname="$1"
	local secval

	if ! ls_secret_verify "$secname"; then
		# Skip secrets that can't be verified
		printf "  {\n"
		printf "    \"name\": %s,\n" "$(ls_json_string "$secname")"
		printf "    \"error\": %s\n" "$(ls_json_string "Unable to validate secret authenticity")"
		printf "  }"
	elif ! secval=$(ls_secret_get "$secname"); then
		# Skip secrets that can't be retrieved
		printf "  {\n"
		printf "    \"name\": %s,\n" "$(ls_json_string "$secname")"
		printf "    \"error\": %s\n" "$(ls_json_string "Unable to retrieve secret")"
		printf "  }"
	else
		printf '  {\n'
		ls_json_emit_secret_value "$secname" "$secval" '    '
		printf '\n  }'
	fi
}

# -----------------------------------------------------------------------------
#
# INFO
#
# -----------------------------------------------------------------------------

function ls_info {
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then
		ls_log_error "No littlesecrets store found"
		return 1
	fi

	# Get absolute path to store
	local abs_path
	abs_path="$(realpath "$store")"

	# Get unique users (extract username before colon)
	local users
	users=$(ls_user_list | cut -d: -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')

	# Get secrets
	local secrets
	secrets=$(ls_secret_list | tr '\n' ' ' | sed 's/ $//')

	# List ancestor stores other than the current store.
	local repositories=""
	local repository
	for repository in $(ls_store_list); do
		if [ "$(realpath "$repository")" != "$abs_path" ]; then
			repositories+="$(realpath "$repository") "
		fi
	done
	repositories="${repositories% }"

	if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
		# JSON output format
		echo "{"
		printf '  "path": %s,\n' "$(ls_json_string "$abs_path")"
		local -a user_values=()
		local -a secret_values=()
		local -a repository_values=()
		read -r -a user_values <<<"$users"
		read -r -a secret_values <<<"$secrets"
		read -r -a repository_values <<<"$repositories"
		printf '  "users": '
		ls_json_emit_string_array '' "${user_values[@]}"
		printf ',\n  "secrets": '
		ls_json_emit_string_array '' "${secret_values[@]}"
		printf ',\n  "repositories": '
		ls_json_emit_string_array '' "${repository_values[@]}"
		printf '\n'
		echo "}"
	else
		# Default text output format
		echo "Path: $abs_path"
		if [ -n "$users" ]; then
			echo "Users: $users"
		else
			echo "Users: (none)"
		fi
		if [ -n "$secrets" ]; then
			echo "Secrets: $secrets"
		else
			echo "Secrets: (none)"
		fi
		if [ -n "$repositories" ]; then
			echo "Repositories: $repositories"
		else
			echo "Repositories: (none)"
		fi
	fi
}

function ls_secret_find {
	local pattern="${1:-}"
	if [ -z "$pattern" ]; then
		ls_log_error "find: Missing secret pattern"
		return 1
	fi

	local found=0
	local repository
	local secret_path
	local secret_name
	for repository in $(ls_store_list); do
		for secret_path in "$repository"/secret/*/secret.enc; do
			if [ ! -e "$secret_path" ]; then
				continue
			fi
			secret_name="$(basename "$(dirname "$secret_path")")"
			if ls_match "$secret_name" "$pattern" >/dev/null; then
				printf '%s: %s\n' "$secret_name" "$(realpath "$repository")"
				found=1
			fi
		done
	done
	if [ "$found" -eq 0 ]; then
		return 1
	fi
}

function ls_cli_error {
	ls_log_error "$*"
	return 1
}

function ls_cli_help {
	local command="${1:-}"
	if [ -n "$command" ]; then
		local help_line
		help_line="$(grep -E "^[[:space:]]## [^:]+: ((${command})(\||[[:space:]])|${command}[[:space:]])" "$LITTLESECRETS_SCRIPT_PATH" | head -n 1 || true)"
		if [ -z "$help_line" ]; then
			ls_cli_error "Unknown command: $command"
			return 1
		fi
		printf 'Usage: littlesecrets %s\n\n' "$(printf '%s\n' "$help_line" | sed -E 's/^[[:space:]]## [^:]+: //; s/[[:space:]]{2,}.*$//')"
		printf '%s\n' "$help_line" | sed -E 's/^[[:space:]]## [^:]+: [^[:space:]]+([[:space:]]+[^[:space:]]+)*[[:space:]]{2,}//'
		return 0
	fi
	echo "Usage: littlesecrets [GLOBAL_OPTION]... COMMAND [ARGUMENT]..."
	echo ""
	echo "Arguments: <NAME> required, [NAME] optional, <NAME>... one or more, [NAME...] zero or more"
	echo "Expressions ending in _EXPR are shell globs; quote them to prevent shell expansion."
	echo "Global options must appear before COMMAND. The nearest .littlesecrets store is used by default."
	echo ""
	echo "Options:"
	printf '  %-25s  %s\n' '-h, --help' 'Show this help message'
	printf '  %-25s  %s\n' '-v, --version' 'Show version information'
	printf '  %-25s  %s\n' '-q, --quiet' 'Suppress warnings and routine diagnostics'
	printf '  %-25s  %s\n' '--verbose' 'Show routine details and progress'
	printf '  %-25s  %s\n' '--debug' 'Show diagnostic details and error stack traces'
	printf '  %-25s  %s\n' '-k, --key PRIVATE_KEY' 'Set the private key used for decryption'
	printf '  %-25s  %s\n' '-u, --user USER' "Set the user name (default: \$USER)"
	printf '  %-25s  %s\n' '--host HOST' "Set the host name (default: \$HOSTNAME)"
	printf '  %-25s  %s\n' '-s, --store PATH' 'Set the store path (default: .littlesecrets)'
	printf '  %-25s  %s\n' '-f, --format FORMAT' 'Set output format: text or json'
	printf '  %-25s  %s\n' '--binary' 'Use base64 for binary values in JSON output'
	printf '  %-25s  %s\n' '--text' 'Force text values in JSON output'
	echo ""
	grep '^[[:space:]]## [^:]*:' "$LITTLESECRETS_SCRIPT_PATH" |
		sed -E 's/^[[:space:]]## ([^:]+): /\1\t/' |
		awk -F '\t' '
		{
			separator = index($2, "  ")
			syntax = substr($2, 1, separator - 1)
			description = substr($2, separator + 2)
			if (length(syntax) > width) width = length(syntax)
			entries[++count] = $1 SUBSEP syntax SUBSEP description
		}
		END {
			for (i = 1; i <= count; i++) {
				split(entries[i], parts, SUBSEP)
				items[parts[1]] = items[parts[1]] sprintf("  %-" width "s  %s\n", parts[2], parts[3])
			}
			for (i = 1; i <= 7; i++) {
				category = (i == 1 ? "Store" : i == 2 ? "Secrets" : i == 3 ? "Access" : i == 4 ? "Users" : i == 5 ? "Integrity" : i == 6 ? "Shell" : "Meta")
				if (items[category] != "") printf "%s:\n%s", category, items[category]
			}
		}'
}

# -----------------------------------------------------------------------------
#
# CLI
#
# -----------------------------------------------------------------------------

function ls_cli {
	local binary_requested=0
	local text_requested=0

	# Parse global options first

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-q | --quiet)
			LS_LOG_FILTER=""
			shift
			;;
		--verbose)
			LS_LOG_FILTER="warning tip action message progress"
			shift
			;;
		--debug)
			LS_LOG_FILTER="warning tip action message progress output debug"
			shift
			;;
		--)
			shift
			break
			;;
		-k | --key)
			if [ $# -lt 2 ]; then ls_cli_error "$1 requires PRIVATE_KEY"; return 1; fi
			LITTLESECRETS_KEY="$2"
			shift 2
			;;
		-u | --user)
			if [ $# -lt 2 ]; then ls_cli_error "$1 requires USER"; return 1; fi
			LITTLESECRETS_USER="$2"
			shift 2
			;;
		--host)
			if [ $# -lt 2 ]; then ls_cli_error "$1 requires HOST"; return 1; fi
			LITTLESECRETS_HOST="$2"
			shift 2
			;;
		-s | --store)
			if [ $# -lt 2 ]; then ls_cli_error "$1 requires PATH"; return 1; fi
			LITTLESECRETS_STORE="$2"
			shift 2
			;;
		--binary)
			# Force JSON/base64 encoding of value fields (when in JSON mode)
			LITTLESECRETS_FORCE_ENCODING="base64"
			binary_requested=1
			shift
			;;
		--text)
			# Force treat values as text (never base64) even if detection says binary
			LITTLESECRETS_FORCE_ENCODING="text"
			text_requested=1
			shift
			;;
		-fjson)
			# Handle -fjson format (combined flag and value)
			LITTLESECRETS_FORMAT="json"
			shift
			;;
		--format=json)
			# Handle --format=json format (combined long flag and value)
			LITTLESECRETS_FORMAT="json"
			shift
			;;
		-f | --format)
			if [ $# -lt 2 ]; then ls_cli_error "$1 requires FORMAT (text or json)"; return 1; fi
			if [ "$2" != "text" ] && [ "$2" != "json" ]; then ls_cli_error "Invalid format: $2 (expected text or json)"; return 1; fi
			# Handle -f json format (separate flag and value)
			LITTLESECRETS_FORMAT="$2"
			shift 2
			;;
		-h | --help)
			ls_cli help
			return 0
			;;
		-v | --version)
			ls_cli version
			return 0
			;;
		--* | -*)
			ls_log_error "Unknown option $1"
			return 1
			;;
		*)
			break
			;;
		esac
	done

	local cmd="${1:-}"
	shift || true
	if [ "$binary_requested" -eq 1 ] && [ "$text_requested" -eq 1 ]; then
		ls_cli_error "--binary and --text cannot be used together"
		return 1
	fi
	if [ "$binary_requested" -eq 1 ] || [ "$text_requested" -eq 1 ]; then
		if [ "${LITTLESECRETS_FORMAT:-}" != "json" ]; then
		ls_cli_error "--binary and --text require --format json"
		return 1
		fi
	fi
	if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
		ls_cli_help "$cmd"
		return $?
	fi

	case "$cmd" in
	## Meta: help [COMMAND]  Show help for a command
	"help" | h)
		if [ "$#" -gt 1 ]; then ls_cli_error "Usage: littlesecrets help [COMMAND]"; return 1; fi
		ls_cli_help "${1:-}"
		return $?
		;;
	## Meta: version  Show version information
	"version" | v)
		if [ "$#" -ne 0 ]; then ls_cli_error "version accepts no arguments"; return 1; fi
		echo "littlesecrets version $LITTLESECRETS_VERSION"
		return 0
		;;
	## Store: init [DIRECTORY]  Create DIRECTORY/.littlesecrets
	"init")
		if [ "$#" -gt 1 ]; then ls_cli_error "init accepts at most DIRECTORY"; return 1; fi
		ls_store_init "${1:-.}"
		;;
	## Secrets: list|ls [SECRET_EXPR...]  List secret names and recipients
	"list" | "ls")
		if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
			# JSON output format: {"secret.name": ["user@host", ...]}
			local first=true
			echo "{"
			for SECRET in $(ls_secret_list "$@"); do
				if [ "$first" = true ]; then
					first=false
				else
					echo ","
				fi
				# Collect keys into array
				local keys_array=()
				for key in $(ls_secret_keys "$SECRET"); do
					keys_array+=("$key")
				done
				ls_json_emit_key_array "$SECRET" "${keys_array[@]}"
			done
			echo ""
			echo "}"
		else
			# Default text output format
			for SECRET in $(ls_secret_list "$@"); do
				echo "${BOLD}$SECRET${RESET}: ${DIM}$(ls_secret_keys "$SECRET")${RESET}"
			done
		fi
		;;
	## Secrets: get <SECRET>  Write a secret value
	"get")
		if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then ls_cli_error "Usage: littlesecrets get <SECRET>"; return 1; fi
		if [ -z "${1:-}" ]; then
			ls_log_error "get: Missing secret name"
			return 1
		elif ! ls_secret_path "$1" >/dev/null; then
			ls_log_error "Secret does not exist: $1"
			# TODO: Should find approximate matches
			return 1

		elif [ -n "$(ls_option hmac)" ] && ! ls_secret_verify "$1"; then
			ls_log_error "Secret HMAC cannot be validated: $1"
			ls_log_error "Secret signature differs: $1"
			ls_log_tip "Secret likely has been updated and your key is out of date"
			return 1
		else
			local secret_value
			if secret_value=$(ls_secret_get "$1" "${2:-}"); then
				if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
					ls_secret_emit_json "$1" "$secret_value"
				else
					# Default text output format
					echo -n "$secret_value"
				fi
				return 0
			else
				return 1
			fi
		fi
		;;
	## Secrets: add|set <SECRET> [VALUE]  Set a value, or read it from stdin
	"add" | "set")
		if [ "$#" -lt 1 ] || [ "$#" -gt 4 ]; then ls_cli_error "Usage: littlesecrets add|set <SECRET> [VALUE]"; return 1; fi
		if [ -z "${1:-}" ]; then
			ls_log_error "add: Missing secret name"
			return 1
		fi
		if [ -n "${2:-}" ]; then
			ls_log_tip "Passing secret values as arguments can leak secrets in process lists. Prefer passing via stdin."
			# Content provided as argument
			if ls_secret_add "$1" "$2" "${3:-}" "${4:-}" >/dev/null; then
				if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
					local secret_value
					if secret_value=$(ls_secret_get "$1" "${3:-}"); then
						ls_secret_emit_json "$1" "$secret_value"
					fi
				fi
				return 0
			else
				return $?
			fi
		else
			# Read content from stdin
			if ls_secret_add "$1" "" "${2:-}" "${3:-}" >/dev/null; then
				if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
					local secret_value
					if secret_value=$(ls_secret_get "$1" "${2:-}"); then
						ls_secret_emit_json "$1" "$secret_value"
					fi
				fi
				return 0
			else
				return $?
			fi
		fi
		;;
	## Integrity: hash [SECRET_EXPR...]  Create or update HMACs
	"hash")
		local secret
		local hmac_path
		local hmac
		for secret in $(ls_secret_list "$@"); do
			secret="${secret%%:*}"
			hmac_path="$(ls_secret_hmac_path "$secret")"
			hmac="$(ls_secret_hmac "$secret")"
			if [ ! -e "$hmac_path" ]; then
				ls_log_action "Creating HMAC for secret $secret at $hmac_path"
				echo -n "$hmac" >"$hmac_path"
			elif [ "$(cat "$hmac_path")" != "$hmac" ]; then
				ls_log_warning "Existing HMAC differs for secret $secret, updating."
				echo -n "$hmac" >"$hmac_path"
			fi
		done
		;;
	## Integrity: verify [SECRET_EXPR...]  Verify HMACs without modifying secrets
	"verify")
		local -a created=()
		local -a valid=()
		local -a invalid=()
		local -a nokey=()
		local secret_name
		local hmac_path
		local hmac
		for secret_name in $(ls_secret_list "$@"); do
			secret_name="${secret_name%%:*}"
			hmac_path="$(ls_secret_hmac_path "$secret_name")"
			ls_log_progress "Verifying $secret_name"
			if [ ! -e "$hmac_path" ]; then
				# NOTE: Leaving this for reference
				if hmac=$(ls_secret_hmac "$secret_name"); then
					ls_log_progress "Created HMAC: $secret_name"
					ls_log_action "Creating HMAC signature for secret: $secret_name"
					echo -n "$hmac" >"$hmac_path"
					created+=("$secret_name")
				else
					nokey+=("$secret_name")
					ls_log_progress "No HMAC: $secret_name"
				fi
			elif [ "$(cat "$hmac_path")" != "$(ls_secret_hmac "$secret_name")" ]; then
				ls_log_warning "Existing HMAC differs for secret $secret_name"
				ls_log_tip "Most likely the original secret has changed and you haven't been granted the key."
				invalid+=("$secret_name")
				ls_log_progress "Invalid HMAC: $secret_name"
			else
				valid+=("$secret_name")
				ls_log_progress "Valid HMAC: $secret_name"
			fi
		done
		if [ ${#valid[@]} -ne 0 ]; then ls_log_message "Valid: ${GREEN}${valid[*]}${RESET}"; fi
		if [ ${#invalid[@]} -ne 0 ]; then ls_log_message "Invalid: ${RED}${invalid[*]}${RESET}"; fi
		if [ ${#nokey[@]} -ne 0 ]; then ls_log_message "Unverified: ${BLUE}${nokey[*]}${RESET}"; fi
		if [ ${#created[@]} -ne 0 ]; then ls_log_message "Created: ${GREEN}${created[*]}${RESET}"; fi
		if [ ${#invalid[@]} -eq 0 ]; then
			return 0
		else
			return 1
		fi
		;;
	## Secrets: remove <SECRET>  Remove a secret
	"remove")
		if [ "$#" -ne 1 ]; then ls_cli_error "Usage: littlesecrets remove <SECRET>"; return 1; fi
		if [ -z "${1:-}" ]; then
			ls_log_error "remove: Missing secret name"
			return 1
		fi
		ls_secret_remove "$1"
		return $?
		;;
	## Access: grant <SECRET_EXPR> <USER_EXPR...>  Grant matching users access
	"grant")
		if [ "$#" -lt 2 ]; then ls_cli_error "Usage: littlesecrets grant <SECRET_EXPR> <USER_EXPR...>"; return 1; fi
		if [ -z "${1:-}" ]; then
			ls_log_error "grant: Missing secret name, expecting SECRETS USER"
			return 1
		elif [ -z "${2:-}" ]; then
			ls_log_error "grant: Missing user name, expecting SECRET USER"
			return 1
		fi
		ls_secret_grant "$1" "${@:2}"
		return $?
		;;
	## Access: revoke <SECRET_EXPR> <USER_EXPR...>  Revoke matching users' access
	"revoke")
		if [ "$#" -lt 2 ]; then ls_cli_error "Usage: littlesecrets revoke <SECRET_EXPR> <USER_EXPR...>"; return 1; fi
		if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
			ls_log_error "revoke: Missing secret name or user pattern"
			return 1
		fi
		ls_secret_revoke "$1" "${@:2}"
		return $?
		;;
	## Users: register [USER[@HOST]] [PUBLIC_KEY]  Register a public key
	"register")
		if [ "$#" -gt 2 ]; then ls_cli_error "Usage: littlesecrets register [USER[@HOST]] [PUBLIC_KEY]"; return 1; fi
		ls_user_register "${1:-}" "${2:-}"
		return $?
		;;
	## Users: deregister <USER[@HOST]> [PUBLIC_KEY]  Remove registered public keys
	"deregister")
		if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then ls_cli_error "Usage: littlesecrets deregister <USER[@HOST]> [PUBLIC_KEY]"; return 1; fi
		if [ -z "${1:-}" ]; then
			ls_log_error "deregister: Missing user"
			return 1
		fi
		ls_user_deregister "$1" "${2:-}"
		return $?
		;;
	## Users: users [USER_EXPR...]  List registered users and hosts
	"users")
		if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
			# JSON output format: {"user.name": ["user.host", ...]}
			echo "{"
			local first=true
			local users
			users=$(ls_user_list "$@")
			if [ -n "$users" ]; then
				# Group users by username
				local -A user_hosts
				while IFS=':' read -r username hostname; do
					if [ -n "$username" ] && [ -n "$hostname" ]; then
						user_hosts["$username"]+="$hostname "
					fi
				done <<<"$users"

				# Output JSON object
				for username in "${!user_hosts[@]}"; do
					if [ "$first" = true ]; then
						first=false
					else
						echo ","
					fi
					printf '  %s: [' "$(ls_json_string "$username")"
					local hosts="${user_hosts[$username]}"
					local host_first=true
					for host in $hosts; do
						if [ -n "$host" ]; then
							if [ "$host_first" = true ]; then
								host_first=false
							else
								printf ', '
							fi
							printf '%s' "$(ls_json_string "$host")"
						fi
					done
					printf ']'
				done
			fi
			echo ""
			echo "}"
		else
			# Default text output format
			ls_user_list "$@"
		fi
		return $?
		;;
	## Access: access [SECRET_EXPR...]  List recipients by secret
	"access")
		if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
			# JSON output format: {"secret.name": ["user@host", ...]}
			echo "{"
			local first=true
			if [ -z "${1:-}" ]; then
				# No arguments, show access for all secrets
				for secret in $(ls_secret_list); do
					if [ "$first" = true ]; then
						first=false
					else
						echo ","
					fi
					printf '  %s: [' "$(ls_json_string "$secret")"
					local users
					users=$(ls_secret_users "$secret")
					local user_first=true
					for user in $users; do
						if [ "$user_first" = true ]; then
							user_first=false
						else
							printf ', '
						fi
						printf '%s' "$(ls_json_string "$user")"
					done
					printf ']'
				done
			else
				# Show access for specific secrets
				for secret in $(ls_secret_list "$@"); do
					if [ "$first" = true ]; then
						first=false
					else
						echo ","
					fi
					printf '  %s: [' "$(ls_json_string "$secret")"
					local users
					users=$(ls_secret_users "$secret")
					local user_first=true
					for user in $users; do
						if [ "$user_first" = true ]; then
							user_first=false
						else
							printf ', '
						fi
						printf '%s' "$(ls_json_string "$user")"
					done
					printf ']'
				done
			fi
			echo ""
			echo "}"
		else
			# Default text output format
			if [ -z "${1:-}" ]; then
				ls_secret_users
				return $?
			else
				for secret in $(ls_secret_list "$@"); do
					echo -n "$secret:"
					ls_secret_users "$secret"
					echo
				done
			fi
		fi
		;;
	## Shell: export [VAR=SECRET...]  Output shell assignments for secrets
	"export")
		ls_secret_export "$@"
		return $?
		;;
	## Secrets: ensure <SECRET>  Return a value, creating it if missing
	"ensure")
		if [ "$#" -ne 1 ]; then ls_cli_error "Usage: littlesecrets ensure <SECRET>"; return 1; fi
		ls_secret_ensure "$@"
		return $?
		;;
	## Secrets: has <SECRET_EXPR...>  Exit 0 when any secret matches
	"has")
		if [ -z "${1:-}" ]; then
			ls_log_error "has: Missing secret pattern"
			return 1
		fi
		local found_secrets
		found_secrets=$(ls_secret_list "$@")
		if [ -n "$found_secrets" ]; then
			return 0
		else
			return 1
		fi
		;;
	## Store: find <SECRET_EXPR>  Find secrets in every ancestor store
	"find")
		if [ "$#" -ne 1 ]; then ls_cli_error "Usage: littlesecrets find <SECRET_EXPR>"; return 1; fi
		ls_secret_find "$@"
		return $?
		;;
	## Store: info  Show the active and ancestor stores
	"info")
		if [ "$#" -ne 0 ]; then ls_cli_error "info accepts no arguments"; return 1; fi
		ls_info "$@"
		return $?
		;;
	*)
		if [ -n "$cmd" ]; then
			ls_log_error "Unknown command: '$cmd'"
		fi
		ls_cli --help
		return 1
		;;

	esac
}

# -----------------------------------------------------------------------------
#
# MAIN
#
# -----------------------------------------------------------------------------

function ls_trap_extract {
	local sig="$1"
	local t
	t="$(trap -p "$sig" || true)"
	if [ -n "$t" ]; then
		sed -E "s/^trap -- '(.*)' [A-Z0-9]+$/\1/" <<<"$t"
	fi
}

LS_TRAP_EXIT_PREVIOUS="$(ls_trap_extract EXIT)"
LS_TRAP_ERROR_PREVIOUS=""
trap ls_cleanup EXIT INT TERM

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	ls_cli "$@"
else
	# We only register error handling in library mode
	LS_TRAP_ERROR_PREVIOUS="$(ls_trap_extract ERR)"
	trap ls_on_error ERR
fi

# EOF
