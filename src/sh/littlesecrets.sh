#!/usr/bin/env bash
#  _ _ _   _   _      __                    _
# | (_) |_| |_| | ___/ _\ ___  ___ _ __ ___| |_ ___
# | | | __| __| |/ _ \ \ / _ \/ __| '__/ _ \ __/ __|
# | | | |_| |_| |  __/\ \  __/ (__| | |  __/ |_\__ \
# |_|_|\__|\__|_|\___\__/\___|\___|_|  \___|\__|___/
#
# (c) LittleWorshop Ltd, 2025, BSD 3-Clause License

# --
# A simplified, reduced version of LittleSecrets that works only with
# the shell and simple tools.

set -euo pipefail
shopt -s extglob
umask 077

# -----------------------------------------------------------------------------
#
# PORTABLE PATH UTILITIES
#
# -----------------------------------------------------------------------------

# Function: ls_realpath PATH
# Portable canonical path resolution. Prefers `realpath -m` (GNU) but falls
# back to cd/pwd -P and symlink resolution for macOS/BSD, tolerating a missing
# final path component. Defined before the configuration block because the
# script path is resolved with it at load time.
function ls_realpath { # PATH
	local path="${1:-}"
	[ -n "$path" ] || return 1
	# Prefer GNU `realpath -m`, which also resolves a missing final component.
	local resolved
	if resolved="$(realpath -m -- "$path" 2>/dev/null)"; then
		printf '%s\n' "$resolved"
		return 0
	fi
	# Resolve inside a subshell so `set -f` cannot leak into the caller.
	(
		local head tail canon out comp
		# Make absolute so relative inputs resolve against the current directory.
		case "$path" in
		/*) ;;
		*) path="$PWD/$path" ;;
		esac
		# Split into the deepest existing directory prefix and any trailing
		# components (files or missing paths), like `realpath -m`.
		head="$path"
		tail=""
		while [ ! -d "$head" ] && [ "$head" != "/" ]; do
			tail="${head##*/}${tail:+/$tail}"
			head="${head%/*}"
			[ -n "$head" ] || head="/"
		done
		if ! canon="$(cd "$head" 2>/dev/null && pwd -P)"; then
			exit 1
		fi
		resolved="$canon${tail:+/$tail}"
		# Follow a symlinked final component (GNU realpath resolves these too).
		local link_target
		local link_guard=0
		while [ -L "$resolved" ] && [ "$link_guard" -lt 40 ]; do
			link_target="$(readlink "$resolved" 2>/dev/null)" || break
			case "$link_target" in
			/*) resolved="$link_target" ;;
			*) resolved="$(dirname "$resolved")/$link_target" ;;
			esac
			link_guard=$((link_guard + 1))
		done
		# Normalize any remaining `.`/`..` lexically.
		out=""
		local IFS='/'
		set -f
		for comp in $resolved; do
			case "$comp" in
			'' | '.') ;;
			'..') out="${out%/*}" ;;
			*) out="$out/$comp" ;;
			esac
		done
		printf '%s\n' "${out:-/}"
	)
}

# --
# We define the main internal variables
declare -a LS_CLEANUP=()
LS_CLEANUP+=("")
declare -a LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
LS_TEMP_OWNER="$BASHPID"
LS_TEMP_DIR=""

LITTLESECRETS_VERSION="1.1.0"

# --
# And define the configuration
LITTLESECRETS_USER=${LITTLESECRETS_USER:-$USER}
LITTLESECRETS_HOST=${LITTLESECRETS_HOST:-$HOSTNAME}
LITTLESECRETS_KEY=${LITTLESECRETS_KEY:-$HOME/.ssh/id_rsa}
LITTLESECRETS_STORE_NAME=".littlesecrets"
LITTLESECRETS_STORE=${LITTLESECRETS_STORE:-$LITTLESECRETS_STORE_NAME}
LITTLESECRETS_FORMAT=${LITTLESECRETS_FORMAT:-}
LITTLESECRETS_FORMAT_VERSION=${LITTLESECRETS_FORMAT_VERSION:-v2}
LITTLESECRETS_FORCE_ENCODING=${LITTLESECRETS_FORCE_ENCODING:-}
LITTLESECRETS_ALLOW_LEGACY=${LITTLESECRETS_ALLOW_LEGACY:-0}
# Resolve the script path; ls_realpath falls back to a portable implementation
# when GNU `realpath` is unavailable (macOS/BSD), and the final fallback keeps
# the raw BASH_SOURCE path if even that fails.
LITTLESECRETS_SCRIPT_PATH="$(ls_realpath "${BASH_SOURCE[0]}")" ||
	LITTLESECRETS_SCRIPT_PATH="${BASH_SOURCE[0]}"
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
	
	# This is a compatibility check, not authentication of the executable.
	if ! "$resolved_bin" version 2>/dev/null | grep -qiE "openssl|libressl"; then
		echo "WARNING: '$resolved_bin' does not appear to be OpenSSL or LibreSSL" >&2
		echo "Output from '$resolved_bin version':" >&2
		"$resolved_bin" version 2>&1 | head -3 >&2
		echo "Proceeding anyway, but cryptographic operations may fail" >&2
	fi
	
	echo "$resolved_bin"
}
# The executable and PATH must come from the trusted local environment.
LITTLESECRETS_OPENSSL_BIN="$(ls_validate_openssl_bin "${LITTLESECRETS_OPENSSL_BIN:-openssl}")"
readonly LITTLESECRETS_OPENSSL_BIN
# --
# Historical options retained for library callers; authentication is mandatory.
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

# Function: ls_path_age PATH
# Emits the age in seconds of PATH's last modification, or nothing when it
# cannot be determined. Tries the GNU then the BSD `stat` interfaces.
function ls_path_age { # PATH
	local path="${1:-}"
	local mtime now
	[ -e "$path" ] || return 1
	if mtime="$(stat -c %Y -- "$path" 2>/dev/null)" ||
		mtime="$(stat -f %m "$path" 2>/dev/null)"; then
		now="$(date +%s)"
		[ "$mtime" -le "$now" ] || return 1
		printf '%s\n' "$((now - mtime))"
		return 0
	fi
	return 1
}

# Portable locks never steal another process's lock, including stale locks.
# After SIGKILL, the operator must remove the abandoned lock explicitly.
function ls_lock_acquire { # LOCKDIR [TIMEOUT_SECONDS]
	local lock_dir="${1:-}"
	local timeout="${2:-${LS_LOCK_TIMEOUT:-300}}"
	local waited=0
	local token="${BASHPID}.${RANDOM}.${RANDOM}"
	[ -n "$lock_dir" ] || return 1
	[[ "$timeout" =~ ^[0-9]+$ ]] || return 1
	while true; do
		if mkdir "$lock_dir" 2>/dev/null; then
			if ! printf '%s\n' "$BASHPID" >"$lock_dir/pid" ||
				! printf '%s\n' "$token" >"$lock_dir/token"; then
				rm -f -- "$lock_dir/pid" "$lock_dir/token"
				rmdir -- "$lock_dir" 2>/dev/null || true
				return 1
			fi
			LS_LOCK_PATHS+=("$lock_dir")
			LS_LOCK_TOKENS+=("$token")
			return 0
		fi
		[ ! -L "$lock_dir" ] || return 1
		if [ "$waited" -ge "$timeout" ]; then
			ls_log_error "Lock unavailable: $lock_dir (remove abandoned locks only after checking their holder)"
			return 1
		fi
		sleep 1
		waited=$((waited + 1))
	done
}

# Function: ls_lock_release LOCKDIR
# Releases a lock acquired with ls_lock_acquire.
function ls_lock_release { # LOCKDIR
	local lock_dir="${1:-}"
	local i token
	for i in "${!LS_LOCK_PATHS[@]}"; do
		[ "${LS_LOCK_PATHS[$i]}" = "$lock_dir" ] || continue
		token="${LS_LOCK_TOKENS[$i]}"
		[[ "$token" == "$BASHPID."* ]] || continue
		LS_LOCK_PATHS[i]=""
		LS_LOCK_TOKENS[i]=""
		if [ ! -L "$lock_dir" ] && [ ! -L "$lock_dir/token" ] &&
			[ "$(cat "$lock_dir/token" 2>/dev/null)" = "$token" ]; then
			rm -f -- "$lock_dir/pid" "$lock_dir/token" || return 1
			rmdir -- "$lock_dir" || return 1
		fi
	done
	return 0
}

# --
# Secure creation of a file that will be cleaned up, OK to store secrets
# and keys.
function ls_mkstemp {
	local res
	# The parent owns this directory even when called in $(...).
	res="$(mktemp "$LS_TEMP_DIR/file.XXXXXXXX")" || return 1
	# If there's a second argument, that's going to be the contents, previously
	# encoded.
	if [ -n "${1:-}" ]; then
		if ! printf '%s' "$1" | ls_decode >"$res"; then
			rm -f -- "$res"
			return 1
		fi
	fi
	printf '%s\n' "$res"
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
			ls_secure_mkdir "$parent" || return 1
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
	for path in "${LS_LOCK_PATHS[@]}"; do
		[ -z "$path" ] || ls_lock_release "$path" || true
	done
	for path in "${LS_CLEANUP[@]}"; do
		if [ -z "$path" ]; then
			# nothing
			path=
		elif [ -d "$path" ]; then
			rmdir -- "$path" 2>/dev/null || true
		elif [ -e "$path" ]; then
			unlink "$path"
		fi
	done
	if [ "$BASHPID" = "$LS_TEMP_OWNER" ] && [ -n "$LS_TEMP_DIR" ]; then
		rm -rf -- "$LS_TEMP_DIR"
	fi
	if [ -n "${LS_TRAP_EXIT_PREVIOUS:-}" ]; then
		eval "$LS_TRAP_EXIT_PREVIOUS"
	fi
}

function ls_validate_name { # NAME
	local name="${1:-}"
	if [ -z "$name" ] || [[ "$name" == [.-]* ]]; then
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

# Reject symlinks and special files before entering a store/trust directory.
function ls_safe_path { # PATH
	local path="$1" current="" component
	[[ "$path" == /* ]] || path="$PWD/$path"
	local -a components=()
	IFS=/ read -r -a components <<<"$path"
	[[ "$path" != *$'\n'* ]] || return 1
	for component in "${components[@]}"; do
		case "$component" in
		'' | .) continue ;;
		..) current="${current%/*}"; continue ;;
		esac
		current="$current/$component"
		if [ -L "$current" ] || { [ -e "$current" ] && [ ! -f "$current" ] && [ ! -d "$current" ]; }; then
			ls_log_error "Unsafe filesystem entry: $current"
			return 1
		fi
	done
	LS_SAFE_PATH="${current:-/}"
}

# Pin the directory as cwd; all subsequent writes use single-component names.
function ls_safe_cd { # DIRECTORY
	local CDPATH=""
	ls_safe_path "$1" || return 1
	local expected
	expected="$LS_SAFE_PATH"
	cd -P -- "$1" || return 1
	[ "$(pwd -P)" = "$expected" ] || return 1
}

function ls_secure_mkdir() ( # DIRECTORY
	local CDPATH=""
	ls_safe_path "$1" || return 1
	local path="$LS_SAFE_PATH" component expected=""
	local -a components=()
	IFS=/ read -r -a components <<<"$path"
	cd / || return 1
	for component in "${components[@]}"; do
		[ -n "$component" ] || continue
		expected="$expected/$component"
		if [ ! -e "$component" ]; then mkdir -- "$component" || [ -d "$component" ] || return 1; fi
		[ ! -L "$component" ] && [ -d "$component" ] || return 1
		cd -P -- "$component" || return 1
		[ "$(pwd -P)" = "$expected" ] || return 1
	done
)

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
		# Intentional glob expansion of the internal relative pattern.
		# shellcheck disable=SC2206,SC2086
		for item_path in "$store"/$path; do
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
	ls_is_utf8_file "$path" || return 0
	return 1
}

function ls_is_utf8_file { # PATH
	if command -v iconv >/dev/null 2>&1; then
		iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1
	else
		local count
		count="$(LC_ALL=C tr -d '\000-\177' <"$1" | wc -c)" || return 1
		[ "$count" -eq 0 ]
	fi
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
function ls_ssh_keypair_ensure() ( # KEYPATH
	LS_CLEANUP=()
	LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
	LS_TRAP_EXIT_PREVIOUS=""
	trap ls_cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	local privkey_path="${1:-$LITTLESECRETS_KEY}"
	if [[ "$privkey_path" == *$'\n'* ]]; then
		ls_log_error "SSH private key path is invalid"
		return 1
	fi
	privkey_path="$(ls_realpath "$privkey_path")" || return 1
	ls_mkparent "$privkey_path" || return 1
	local lock_path
	lock_path="${privkey_path}.littlesecrets.lock.d"
	# The source key and its derived files are shared by concurrent CLI processes.
	# Hold one per-source-key lock across their complete initialization. `mkdir`
	# is atomic on POSIX filesystems and, unlike `flock`, is available on macOS.
	# NOTE: pre-portability releases used `${privkey_path}.littlesecrets.lock`
	# as an flock target; the two schemes do not exclude each other, so avoid
	# running this version concurrently with an old one on the same key.
	if ! ls_lock_acquire "$lock_path"; then
		ls_log_error "Could not acquire SSH key lock (timeout): $lock_path"
		return 1
	fi
	# Ensures private key exists, otherwise creates it
	if [ ! -e "$privkey_path" ]; then
		ls_log_message "Missing SSH RSA key: $privkey_path"
		ls_log_action "Creating SSH key using 'ssh-keygen -t rsa -b 4096'"
		ls_log_output_start
		ssh-keygen -q -t rsa -b 4096 -N "" -f "$privkey_path" 2> >(ls_log_external) || return 1
		ls_log_output_end
	fi
	if ! ssh-keygen -y -P "" -f "$privkey_path" >/dev/null 2>&1; then
		ls_log_error "SSH private key with passphrase are not supported: $privkey_path"
		ls_lock_release "$lock_path"
		return 1
	fi
	local key_id
	key_id=$("$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 "$privkey_path" | cut -d' ' -f2 | cut -c1-16) || return 1
	local privkey_parent
	privkey_parent="$(dirname "$privkey_path")"
	local privkey_pem_path="${privkey_parent}/littlesecrets-${key_id}.pem"
	local pubkey_pem_path="${privkey_parent}/littlesecrets-${key_id}.pem.pub"
	# Ensures PEM private key exists, and is up to date
	if [ ! -e "$privkey_pem_path" ] || [ "$privkey_path" -nt "$privkey_pem_path" ]; then
		local privkey_ssh_tmp
		privkey_ssh_tmp="$(ls_mkstemp)" || return 1
		LS_CLEANUP+=("$privkey_ssh_tmp")
		local privkey_pem_tmp
		privkey_pem_tmp="$(ls_mkstemp)" || return 1
		LS_CLEANUP+=("$privkey_pem_tmp")
		ls_log_action "Converting SSH RSA DER key to PEM format: $privkey_pem_path"
		# NOTE: ssh-keygen will overwrite the key, so we copy it
		cat "$privkey_path" >"$privkey_ssh_tmp" || return 1
		# SSH key is in DER format, we need PEM
		ls_log_output_start
		ssh-keygen -q -p -m pem -N '' -f "$privkey_ssh_tmp" > >(ls_log_external) 2> >(ls_log_external) || return 1
		"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$privkey_ssh_tmp" -out "$privkey_pem_tmp" 2> >(ls_log_external) || return 1
		ls_log_output_end
		ls_try_write "$privkey_pem_tmp" "$privkey_pem_path" true || return 1
		chmod 400 "$privkey_pem_path" || return 1
		ls_unlink "$privkey_ssh_tmp"
	fi
	# Ensures PEM public key exists, and is up to date
	if [ ! -e "$pubkey_pem_path" ] || [ "$privkey_pem_path" -nt "$pubkey_pem_path" ]; then
		local pubkey_pem_tmp
		pubkey_pem_tmp="$(ls_mkstemp)" || return 1
		LS_CLEANUP+=("$pubkey_pem_tmp")
		ls_log_action "Deriving PKCS8 public key from RSA PEM private key: $pubkey_pem_path"
		ls_log_output_start
		"$LITTLESECRETS_OPENSSL_BIN" rsa -in "$privkey_pem_path" -pubout -out "$pubkey_pem_tmp" 2> >(ls_log_external) || return 1
		ls_log_output_end
		ls_try_write "$pubkey_pem_tmp" "$pubkey_pem_path" true || return 1
		chmod 400 "$pubkey_pem_path" || return 1
	fi
	if [ ! -e "$privkey_pem_path" ] || [ ! -e "$pubkey_pem_path" ]; then
		ls_log_error "Could not create PEM keypair from SSH keypair: $privkey_path"
		ls_lock_release "$lock_path"
		return 1
	fi
	ls_lock_release "$lock_path"
	printf '%s\n' "$privkey_pem_path"
)

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
	local path
	path="$(ls_ssh_keypair_ensure "$@")" || return 1
	printf '%s.pub\n' "$path"
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
	if ls_is_path "$keypath" && [ -f "$keypath" ]; then
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
		if ! ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" > >(ls_log_external) 2> >(ls_log_external); then
			res=1
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
	if ls_is_path "$key" && [ -f "$key" ]; then
		cat "$key"
	else
		printf '%s' "$key"
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
	local hex offset
	hex="$(cat)" || return 1
	hex="${hex//[[:space:]]/}"
	[[ "$hex" =~ ^([[:xdigit:]]{2})*$ ]] || return 1
	for ((offset = 0; offset < ${#hex}; offset += 2)); do
		printf '%b' "\\x${hex:offset:2}" || return 1
	done
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
	IFS= read -r -N4 prefix || true
	if [ "$prefix" == "@LS:" ]; then
		"$LITTLESECRETS_OPENSSL_BIN" base64 -d -A </dev/stdin
	else
		printf '%s' "$prefix"
		cat </dev/stdin
	fi
}

# --
# Generates a symmetric key usable for a secret. The key is encoded to be
# stored in a variable.
function ls_key {
	"$LITTLESECRETS_OPENSSL_BIN" rand "${1:-32}" | ls_encode
}

# --
function ls_encrypt_sym { # KEY
	local key_path
	key_path=$(ls_mkstemp "$1") || return 1
	local output_path
	output_path=$(ls_mkstemp) || return 1
	local pass_path
	pass_path=$(ls_mkstemp) || return 1
	local openssl_res=0
	ls_log_output_start
	# Convert raw key into hex to avoid line/newline/null truncation in OpenSSL -pass fd:
	ls_bin2hex <"$key_path" >"$pass_path" || return 1
	# NOTE: The fd anonymises the key path.
	exec 3<"$pass_path" || return 1
	if ! "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out "$output_path" -pass fd:3 2> >(ls_log_external); then
		openssl_res=1
		ls_log_error "ls_encrypt_sym: Could not encrypt secret"
	else
		cat "$output_path" || openssl_res=1
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
	key_hex="$(printf '%s' "$key" | ls_bin2hex)" || return 1
	if [ "${#key_hex}" -gt 128 ]; then
		key_hex="$(printf '%s' "$key" | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex)" || return 1
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
	if ! inner_digest=$({ printf '%s' "$inner_hex" | ls_hex2bin && cat "$path"; } | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex); then
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
	key_path=$(ls_mkstemp "$1") || return 1
	local input_path
	input_path=$(ls_mkstemp) || return 1
	local output_path
	output_path=$(ls_mkstemp) || return 1
	local pass_path
	pass_path=$(ls_mkstemp) || return 1
	local legacy_pass_path=
	# Read input first
	cat >"$input_path" || return 1
	ls_bin2hex <"$key_path" >"$pass_path" || return 1
	exec 3<"$pass_path" || return 1
	if ! "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -d -in "$input_path" -out "$output_path" -pass fd:3 2>/dev/null; then
		exec 3<&-
		[ "${LITTLESECRETS_ALLOW_LEGACY:-0}" = 1 ] || return 1
		# Legacy stores used the raw key bytes as the passphrase rather than
		# their hexadecimal representation.
		legacy_pass_path=$(ls_mkstemp) || return 1
		cat "$key_path" >"$legacy_pass_path" || return 1
		exec 3<"$legacy_pass_path" || return 1
		if ! "$LITTLESECRETS_OPENSSL_BIN" aes-256-cbc -md sha512 -salt -pbkdf2 -d -in "$input_path" -out "$output_path" -pass fd:3 2> >(ls_log_external); then
			res=1
			ls_log_error "ls_decrypt_sym: Could not symmetrically decrypt secret [$res]"
		else
			cat "$output_path" || res=1
		fi
	else
		cat "$output_path" || res=1
	fi
	exec 3<&-
	ls_log_output_end
	ls_unlink "$key_path" "$input_path" "$output_path" "$pass_path" "$legacy_pass_path"
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
		pubkey_path="$(ls_pubkey_path)" || return 1
	elif ls_is_path "$pubkey" && [ -f "$pubkey" ]; then
		pubkey_path="$pubkey"
	else
		pubkey_path="$(ls_mkstemp "$pubkey")" || return 1
		pubkey_temp=1
	fi
	ls_log_output_start
	local output_path
	output_path=$(ls_mkstemp) || return 1
	if ! "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -encrypt -pubin -inkey "$pubkey_path" -in "${secret_path}" -out "$output_path" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2> >(ls_log_external); then
		res=1
		ls_log_error "ls_encrypt_asym: Could not asymmetrically encrypt secret"
	else
		cat "$output_path" || res=1
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
	local input_temp=0
	local res=0
	if [ "$secret_path" = "/dev/stdin" ]; then
		local input_path
		input_path="$(ls_mkstemp)" || return 1
		cat >"$input_path" || return 1
		secret_path="$input_path"
		input_temp=1
	fi
	if [ -z "$privkey" ]; then
		privkey_path="$(ls_privkey_path)" || return 1
	elif ls_is_path "$privkey" && [ -f "$privkey" ]; then
		privkey_path="$privkey"
	else
		privkey_path="$(ls_mkstemp "$privkey")" || return 1
		privkey_temp=1
	fi
	ls_log_output_start
	local output_path
	output_path=$(ls_mkstemp) || return 1
	# New stores use OAEP-SHA256. Retry with the legacy PKCS#1 v1.5
	# padding used by older stores when OAEP decryption fails.
	if ! "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -decrypt -inkey "$privkey_path" -in "$secret_path" -out "$output_path" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2>/dev/null; then
		[ "${LITTLESECRETS_ALLOW_LEGACY:-0}" = 1 ] || return 1
		if ! "$LITTLESECRETS_OPENSSL_BIN" pkeyutl -decrypt -inkey "$privkey_path" -in "$secret_path" -out "$output_path" -pkeyopt rsa_padding_mode:pkcs1 2> >(ls_log_external); then
			res=1
			ls_log_error "ls_decrypt_asym: Could not asymmetrically decrypt secret [$res]"
		else
			cat "$output_path" || res=1
		fi
	else
		cat "$output_path" || res=1
	fi
	ls_log_output_end
	unlink "$output_path"
	if [ "$input_temp" == 1 ]; then
		unlink "$secret_path"
	fi
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
	local store
	store="$(ls_find "$LITTLESECRETS_STORE")" || return 1
	store="$(CDPATH= cd -P -- "$store" && pwd -P)" || return 1
	ls_safe_path "$store" || return 1
	[ -d "$store" ] || return 1
	printf '%s\n' "$LS_SAFE_PATH"
}

function ls_store_list {
	ls_find_all "$LITTLESECRETS_STORE"
}

function ls_store_init {
	ls_store_initialize "${1:-.}/$LITTLESECRETS_STORE_NAME"
}

function ls_store_initialize() ( # STORE
	local store="$1" tmp
	ls_safe_path "$store" || return 1
	ls_secure_mkdir "$store/secret" && ls_secure_mkdir "$store/user" || return 1
	store="$(ls_realpath "$store")" || return 1
	ls_safe_cd "$store" || return 1
	LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
	trap 'ls_lock_release .init.lock.d' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	ls_lock_acquire .init.lock.d || return 1
	ls_safe_path "$store/store.id" || return 1
	if [ ! -f "$store/store.id" ]; then
		tmp="$(ls_mkstemp)" || return 1
		"$LITTLESECRETS_OPENSSL_BIN" rand -hex 16 >"$tmp" || return 1
		ls_try_write "$tmp" "$store/store.id" true || return 1
	fi
	ls_store_trust "$store" 1 >/dev/null || return 1
	printf '%s\n' "$store"
)

# --
# Ensures that the store exists
function ls_store_ensure {
	ls_store || { ls_log_error "No store found; run init first"; return 1; }
}

# Trust is local to this checkout, outside the shared store. Legacy migration
# may initialize the identity and caller's key after verifying the old HMAC.
function ls_store_trust { # STORE [INITIALIZE]
	local store="$1" initialize="${2:-0}" id digest root trust mode tmp directory
	ls_safe_path "$store/store.id" || return 1
	id="$(cat "$store/store.id")" || return 1
	[[ "$id" =~ ^[a-f0-9]{32}$ ]] || return 1
	digest="$(printf '%s' "$store" | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex)" || return 1
	[[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
	root="${LITTLESECRETS_TRUST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/littlesecrets}"
	ls_safe_path "$root" || return 1
	root="$LS_SAFE_PATH"
	[[ "$root/" != "$store/"* ]] || { ls_log_error "Trust directory must be outside the store"; return 1; }
	trust="$root/$digest"
	if [ "$initialize" = 1 ]; then ls_secure_mkdir "$trust" || return 1; fi
	ls_safe_path "$trust" || return 1
	[ -d "$trust" ] && [ -O "$trust" ] || { ls_log_error "Untrusted store; run init using a trusted checkout"; return 1; }
	for directory in "$root" "$trust"; do
		[ -O "$directory" ] || return 1
		mode="$(stat -c %a "$directory" 2>/dev/null || stat -f %Lp "$directory")" || return 1
		(( (8#$mode & 077) == 0 )) || { ls_log_error "Trust directory must be private: $directory"; return 1; }
	done
	ls_safe_path "$trust/store.id" || return 1
	if [ ! -f "$trust/store.id" ] && [ "$initialize" = 1 ]; then
		tmp="$(ls_mkstemp)" || return 1
		printf '%s\n' "$id" >"$tmp" || return 1
		ls_try_write "$tmp" "$trust/store.id" true || return 1
	fi
	[ "$(cat "$trust/store.id" 2>/dev/null)" = "$id" ] || { ls_log_error "Store identity does not match its local pin"; return 1; }
	printf '%s\n' "$trust"
}

function ls_trusted_pubkey { # REGISTERED_KEY_PATH
	local path="$1" store trust user host pin
	store="$(ls_store)" || return 1
	trust="$(ls_store_trust "$store")" || return 1
	user="$(basename "$(dirname "$path")")"
	host="$(basename "$path" .pubkey)"
	ls_validate_name "$user" && ls_validate_name "$host" || return 1
	pin="$trust/user/$user/$host.pubkey"
	ls_safe_path "$path" && ls_safe_path "$pin" || return 1
	if [ ! -f "$pin" ] || ! cmp -s "$path" "$pin"; then
		ls_log_error "Untrusted public key for $user@$host; register its independently verified key locally"
		return 1
	fi
	printf '%s\n' "$pin"
}

function ls_secret_context { # NAME
	local store trust id
	ls_validate_name "$1" || return 1
	store="$(ls_store)" || return 1
	trust="$(ls_store_trust "$store")" || return 1
	id="$(cat "$trust/store.id")" || return 1
	printf 'LittleSecrets record 3\0%s\0%s\0' "$id" "$1" |
		"$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -binary | ls_bin2hex
}

function ls_record_payload { # DIRECTORY CONTEXT
	local file size base
	local LC_ALL=C
	printf 'LittleSecrets record 3:%s\n' "$2" || return 1
	for file in "$1/secret.format" "$1/secret.signer" "$1/secret.hmac" "$1/secret.enc" "$1"/*.key; do
		[ -f "$file" ] && [ ! -L "$file" ] || return 1
		base="${file##*/}"
		size="$(wc -c <"$file")" || return 1
		size="${size//[[:space:]]/}"
		printf '%s:%s\n' "$base" "$size" && cat "$file" || return 1
	done
}

function ls_record_sign { # NAME DIRECTORY
	local name="$1" dir="$2" context user host key payload
	context="$(ls_secret_context "$name")" || return 1
	user="$(ls_user_name)"; host="$(ls_user_host)"
	ls_validate_name "$user" && ls_validate_name "$host" || return 1
	key="$(ls_privkey_path)" || return 1
	payload="$(ls_mkstemp)" || return 1
	printf '%s@%s' "$user" "$host" >"$dir/secret.signer" || return 1
	ls_record_payload "$dir" "$context" >"$payload" || return 1
	"$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -sign "$key" -out "$dir/secret.sig" "$payload" 2> >(ls_log_external)
}

# Called with the per-secret lock held and cwd pinned to STORE/secret.
function ls_record_copy { # NAME DESTINATION
	local name="$1" destination="$2" file base
	ls_validate_name "$name" || return 1
	ls_safe_path "$name" || return 1
	[ -d "$name" ] || return 1
	for file in "$name"/*; do
		base="${file##*/}"
		case "$base" in
		secret.enc | secret.hmac | secret.format | secret.signer | secret.sig | *@*.key) ;;
		*) ls_log_error "Unexpected record entry: $file"; return 1 ;;
		esac
		[ -f "$file" ] && [ ! -L "$file" ] || return 1
		cat -- "$file" >"$destination/$base" || return 1
	done
	[ -s "$destination/secret.hmac" ] && [ -f "$destination/secret.enc" ]
}

function ls_record_snapshot() ( # NAME DESTINATION
	local store
	store="$(ls_store)" || return 1
	LITTLESECRETS_STORE="$store"
	ls_validate_name "$1" || return 1
	ls_safe_cd "$store/secret" || return 1
	LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
	LS_SNAPSHOT_LOCK=".$1.lock.d"
	trap 'ls_lock_release "$LS_SNAPSHOT_LOCK"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	ls_lock_acquire ".$1.lock.d" || return 1
	ls_record_copy "$1" "$2"
)

function ls_record_transaction_cleanup {
	if [ -n "$LS_TRANSACTION_BACKUP" ] && [ -d "$LS_TRANSACTION_BACKUP/$LS_TRANSACTION_NAME" ] && [ "$LS_TRANSACTION_COMMITTED" = 0 ]; then
		if [ ! -e "$LS_TRANSACTION_NAME" ] && [ ! -L "$LS_TRANSACTION_NAME" ]; then
			mv -- "$LS_TRANSACTION_BACKUP/$LS_TRANSACTION_NAME" ./ || true
		fi
	fi
	[ -z "$LS_TRANSACTION_STAGE" ] || rm -rf -- "$LS_TRANSACTION_STAGE"
	if [ -z "$LS_TRANSACTION_BACKUP" ]; then
		:
	elif [ "$LS_TRANSACTION_COMMITTED" = 1 ] || [ ! -d "$LS_TRANSACTION_BACKUP/$LS_TRANSACTION_NAME" ]; then
		rm -rf -- "$LS_TRANSACTION_BACKUP"
	else
		ls_log_error "Original record retained for recovery at $PWD/$LS_TRANSACTION_BACKUP"
	fi
	ls_lock_release ".$LS_TRANSACTION_NAME.lock.d" || true
}

function ls_record_transaction { # NAME ACTION [ARGS...]
	local LITTLESECRETS_KEY="$LITTLESECRETS_KEY"
	ls_is_path "$LITTLESECRETS_KEY" || { ls_log_error "Private key path is invalid"; return 1; }
	LITTLESECRETS_KEY="$(ls_realpath "$LITTLESECRETS_KEY")" || return 1
	(
	local name="$1" action="$2" store
	shift 2
	ls_validate_name "$name" || return 1
	store="$(ls_store)" || return 1
	LITTLESECRETS_STORE="$store"
	ls_store_trust "$store" >/dev/null || return 1
	ls_safe_cd "$store/secret" || return 1
	LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
	LS_TRANSACTION_NAME="$name"
	LS_TRANSACTION_STAGE="" LS_TRANSACTION_BACKUP="" LS_TRANSACTION_COMMITTED=0
	trap ls_record_transaction_cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	ls_lock_acquire ".$name.lock.d" || return 1
	ls_safe_path "$name" || return 1
	LS_TRANSACTION_STAGE="$(mktemp -d .ls-stage.XXXXXXXX)" || return 1
	LS_TRANSACTION_BACKUP="$(mktemp -d .ls-backup.XXXXXXXX)" || return 1
	mkdir -- "$LS_TRANSACTION_STAGE/$name" || return 1
	"$action" "$name" "$LS_TRANSACTION_STAGE/$name" "$@" || return 1
	ls_safe_path "$name" || return 1
	if [ -e "$name" ]; then
		[ -d "$name" ] || return 1
		mv -- "$name" "$LS_TRANSACTION_BACKUP/" || return 1
	fi
	mv -- "$LS_TRANSACTION_STAGE/$name" ./ || return 1
	LS_TRANSACTION_COMMITTED=1
	)
}

# Authenticate a private snapshot before using its key or returning plaintext.
function ls_record_open { # NAME SNAPSHOT [PRIVATE_KEY]
	local name="$1" dir="$2" private_key="${3:-}" store trust context signer user host payload key envelope expected format
	local LITTLESECRETS_ALLOW_LEGACY="${LITTLESECRETS_ALLOW_LEGACY:-0}"
	if [ -f "$dir/secret.sig" ]; then
		LITTLESECRETS_ALLOW_LEGACY=0
		store="$(ls_store)" || return 1
		trust="$(ls_store_trust "$store")" || return 1
		context="$(ls_secret_context "$name")" || return 1
		signer="$(cat "$dir/secret.signer")" || return 1
		user="${signer%@*}"; host="${signer#*@}"
		[[ "$signer" == *@* ]] && ls_validate_name "$user" && ls_validate_name "$host" || return 1
		key="$trust/user/$user/$host.pubkey"
		ls_safe_path "$key" && [ -f "$key" ] || { ls_log_error "Untrusted signer: $signer"; return 1; }
		payload="$(ls_mkstemp)" || return 1
		ls_record_payload "$dir" "$context" >"$payload" || return 1
		if ! "$LITTLESECRETS_OPENSSL_BIN" dgst -sha256 -verify "$key" -signature "$dir/secret.sig" "$payload" >/dev/null 2>&1; then
			ls_log_error "Record signature or identity is invalid: $name"
			return 1
		fi
		format="$(cat "$dir/secret.format")" || return 1
	else
		if [ -e "$dir/secret.format" ] || [ -e "$dir/secret.signer" ]; then
			ls_log_error "Missing signature on a signed record: $name"
			return 1
		fi
		[ "$LITTLESECRETS_ALLOW_LEGACY" = 1 ] || { ls_log_error "Legacy record requires migration: $name"; return 1; }
		if grep -q '^v2:etm:' "$dir/secret.hmac"; then format=v2; else format=v1; fi
	fi
	[[ "$format" = v1 || "$format" = v2 ]] || return 1
	user="$(ls_user_name)"; host="$(ls_user_host)"
	ls_validate_name "$user" && ls_validate_name "$host" || return 1
	private_key="$(ls_user_privkey "$private_key" | ls_decode)" || return 1
	envelope="$(ls_decrypt_asym "$private_key" "$dir/$user@$host.key")" || return 1
	if [ -f "$dir/secret.sig" ]; then
		[[ "$envelope" == "LS3:$context:"* ]] || { ls_log_error "Recipient key belongs to a different record: $name"; return 1; }
		key="${envelope#LS3:"$context":}"
	else
		[[ "$envelope" != LS3:* ]] || { ls_log_error "Missing signed metadata: $name"; return 1; }
		key="$envelope"
	fi
	[ -n "$key" ] || return 1
	LS_RECORD_KEY="$key" LS_RECORD_FORMAT="$format" LS_RECORD_PLAINTEXT=""
	if [ "$format" = v2 ]; then
		local keys
		keys="$(ls_secret_derive_keys_v2 "$key")" || return 1
		expected="$(ls_secret_hmac_v2 "$dir/secret.enc" "${keys#*:}")" || return 1
	else
		LS_RECORD_PLAINTEXT="$(ls_mkstemp)" || return 1
		ls_decrypt_sym "$key" <"$dir/secret.enc" >"$LS_RECORD_PLAINTEXT" || return 1
		expected="$(ls_secret_hmac - "$key" <"$LS_RECORD_PLAINTEXT")" || return 1
	fi
	if ! cmp -s <(printf '%s' "$expected") "$dir/secret.hmac"; then
		ls_log_error "Secret HMAC verification failed: $name"
		return 1
	fi
}

# Authenticate historical bytes before initializing local trust. The locked
# action rechecks the current record so concurrent readers migrate only once.
function ls_secret_migrate { # NAME [PRIVATE_KEY]
	local name="$1" private_key="${2:-}" store snapshot field
	ls_validate_name "$name" || return 1
	store="$(ls_store)" || return 1
	for field in sig format signer; do
		ls_safe_path "$store/secret/$name/secret.$field" || return 1
		if [ -e "$store/secret/$name/secret.$field" ]; then return 0; fi
	done
	snapshot="$(mktemp -d "$LS_TEMP_DIR/record.XXXXXXXX")" || return 1
	ls_record_snapshot "$name" "$snapshot" || return 1
	local LITTLESECRETS_ALLOW_LEGACY=1
	ls_record_open "$name" "$snapshot" "$private_key" || return 1
	[ ! -f "$snapshot/secret.sig" ] || return 0
	local LITTLESECRETS_KEY="$LITTLESECRETS_KEY"
	if [ -n "$private_key" ]; then
		LITTLESECRETS_KEY="$(ls_mkstemp)" || return 1
		ls_user_privkey "$private_key" | ls_decode >"$LITTLESECRETS_KEY" || return 1
	fi
	ls_store_initialize "$store" >/dev/null || return 1
	ls_user_register >/dev/null || return 1
	ls_record_transaction "$name" ls_secret_migrate_staged || return 1
	ls_log_action "Migrated legacy record '$name' to signed v2"
}

function ls_secret_migrate_staged { # NAME DIRECTORY
	if [ -f "$1/secret.sig" ]; then
		ls_record_copy "$1" "$2" || return 1
		ls_record_open "$1" "$2"
	else
		ls_secret_rekey_staged "$1" "$2" upgrade
	fi
}

function ls_record_read { # NAME SNAPSHOT [PRIVATE_KEY]
	ls_secret_migrate "$1" "${3:-}" || return 1
	ls_record_snapshot "$1" "$2" || return 1
	ls_record_open "$1" "$2" "${3:-}"
}

# =============================================================================
# USERS
# =============================================================================

# --
# Lists all the users in the store
function ls_user_list { # EXPR…
	local store path user host
	store="$(ls_store)" || return 1
	for path in "$store/user"/*/*.pubkey; do
		[ -e "$path" ] || [ -L "$path" ] || continue
		ls_safe_path "$path" || return 1
		user="$(basename "$(dirname "$path")")"; host="$(basename "$path" .pubkey)"
		ls_validate_name "$user" && ls_validate_name "$host" || return 1
		ls_match "$user" "$@" >/dev/null || continue
		printf '%s:%s\n' "$user" "$host"
	done
	return 0
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
	store="$(ls_store_ensure)" || return 1
	local trust tmp
	trust="$(ls_store_trust "$store")" || return 1
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
	local key_source="${2:-}"
	if [ -z "$key_source" ]; then key_source="$(ls_pubkey_path)" || return 1; fi
	key="$(ls_pubkey_import "$key_source")" || return 1
	ls_log_action "Registering user '$user' on '$host'"

	local user_key_path="$store/user/$user/$host.pubkey"
	if [ -z "$key" ]; then
		ls_log_error "Could not import user public key: $(ls_pubkey_path "${1:-}" "${2:-}")"
		return 1
	fi
	tmp="$(ls_mkstemp)" || return 1
	printf '%s\n' "$key" | "$LITTLESECRETS_OPENSSL_BIN" pkey -pubin -pubout >"$tmp" 2> >(ls_log_external) || return 1
	ls_safe_path "$user_key_path" && ls_safe_path "$trust/user/$user/$host.pubkey" || return 1
	ls_secure_mkdir "$store/user/$user" && ls_secure_mkdir "$trust/user/$user" || return 1
	local pin_tmp
	pin_tmp="$(ls_mkstemp)" || return 1
	cat "$tmp" >"$pin_tmp" || return 1
	ls_try_write "$tmp" "$user_key_path" true || return 1
	ls_try_write "$pin_tmp" "$trust/user/$user/$host.pubkey" true || return 1
	printf '%s\n' "$user_key_path"
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
	local registered_users
	registered_users="$(ls_user_list)" || return 1
	for user_expr in "$@"; do
		for registered_user in $registered_users; do
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
	if [ -z "${1:-}" ] && [ -n "$key" ]; then
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
	if [[ "$user" == *@* ]]; then
		printf '%s\n' "${user#*@}"
		return 0
	fi
	if [ -n "$key" ]; then
		local meta
		meta="$(ls_pubkey_meta "$key")"
		if [ -n "$meta" ]; then
			ls_user_host "$meta"
			return 0
		fi
	fi
	printf '%s\n' "$LITTLESECRETS_HOST"
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
		privkey_path=$(ls_privkey_path "$LITTLESECRETS_KEY") || return 1
		if [ -f "$privkey_path" ]; then
			cat "$privkey_path"
		else
			ls_log_error "ls_user_privkey: Could not read the private key"
			return 1
		fi
	else
		local key="$1"
		local key_fmt
		key_fmt=$(ls_key_format "$key") || return 1
		if [[ "$key_fmt" == private:*pkcs8* ]]; then
			# The given keypath is already in the right format
			ls_key_cat "$key"
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
	local store path name
	store="$(ls_store)" || return 1
	ls_safe_path "$store/secret" || return 1
	for path in "$store/secret"/*; do
		[ -e "$path" ] || [ -L "$path" ] || continue
		name="${path##*/}"
		ls_validate_name "$name" || return 1
		ls_match "$name" "$@" || true
	done
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
function ls_try_write() (
	local path_tmp="$1"
	local path_dst="$2"
	local parent base stage=""
	shift 2
	if ! "$@"; then
		ls_log_error "ls_try_write: Action failed, did not update: $path_dst"
		rm -f -- "$path_tmp"
		return 1
	fi
	path_tmp="$(ls_realpath "$path_tmp")" || return 1
	ls_safe_path "$path_dst" || return 1
	[ ! -d "$path_dst" ] || return 1
	parent="$(dirname "$path_dst")"; base="$(basename "$path_dst")"
	ls_safe_cd "$parent" || return 1
	stage="$(mktemp -d .ls-write.XXXXXXXX)" || return 1
	trap 'rm -rf -- "$stage"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	cat "$path_tmp" >"$stage/$base" || return 1
	chmod 600 "$stage/$base" || return 1
	# The destination is a directory, so mv replaces the final entry rather
	# than following it (including a symlink inserted after the check).
	mv -f -- "$stage/$base" ./ || return 1
	rm -f -- "$path_tmp"
)

function ls_secret_write { # NAME PUBKEY? SECRETKEY? FORMAT_VERSION?
	local name="$1" pubkey="${2:-}" store
	ls_validate_name "$name" || { ls_log_error "Invalid secret name: $name"; return 1; }
	store="$(ls_store)" || return 1
	if [ -n "$pubkey" ] && ls_is_path "$pubkey" && [ -f "$pubkey" ]; then
		pubkey="$(ls_realpath "$pubkey")" || return 1
	fi
	# This pin is derived from our local private key, not from the store.
	ls_user_register >/dev/null || return 1
	ls_record_transaction "$name" ls_secret_write_staged "$pubkey" "${3:-}" "${4:-${LITTLESECRETS_FORMAT_VERSION:-v2}}" || return 1
	printf '%s/secret/%s/secret.enc\n' "$store" "$name"
}

function ls_secret_write_staged { # NAME DIRECTORY PUBKEY KEY VERSION [PINNED_RECIPIENTS...]
	local name="$1" dir="$2" pubkey="$3" key="$4" version="$5"
	shift 5
	local plain input context keys hmac user host path pin pubtmp
	local -a recipients=("$@")
	[[ "$version" = v1 || "$version" = v2 ]] || return 1
	[ -n "$key" ] || key="$(ls_key)" || return 1
	plain="$(ls_mkstemp)" || return 1
	cat >"$plain" || return 1
	context="$(ls_secret_context "$name")" || return 1
	input="$(ls_mkstemp)" || return 1
	printf 'LS3:%s:%s' "$context" "$key" >"$input" || return 1
	printf '%s' "$version" >"$dir/secret.format" || return 1
	if [ "$version" = v2 ]; then
		keys="$(ls_secret_derive_keys_v2 "$key")" || return 1
		ls_encrypt_sym "${keys%%:*}" <"$plain" >"$dir/secret.enc" || return 1
		hmac="$(ls_secret_hmac_v2 "$dir/secret.enc" "${keys#*:}")" || return 1
	else
		ls_encrypt_sym "$key" <"$plain" >"$dir/secret.enc" || return 1
		hmac="$(ls_secret_hmac - "$key" <"$plain")" || return 1
	fi
	printf '%s' "$hmac" >"$dir/secret.hmac" || return 1
	if [ -n "$pubkey" ]; then
		user="$(ls_user_name "" "$pubkey")"; host="$(ls_user_host "" "$pubkey")"
		ls_validate_name "$user" && ls_validate_name "$host" || return 1
		pubtmp="$(ls_mkstemp)" || return 1
		ls_pubkey_import "$pubkey" >"$pubtmp" || return 1
		ls_encrypt_asym "$pubtmp" "$input" >"$dir/$user@$host.key" || return 1
	else
		if [ ${#recipients[@]} -eq 0 ]; then
			local listed
			listed="$(ls_user_list_keys)" || return 1
			while IFS= read -r path; do
				[ -n "$path" ] || continue
				pin="$(ls_trusted_pubkey "$path")" || return 1
				recipients+=("$pin")
			done <<<"$listed"
		fi
		[ ${#recipients[@]} -gt 0 ] || return 1
		for pin in "${recipients[@]}"; do
			user="$(basename "$(dirname "$pin")")"; host="$(basename "$pin" .pubkey)"
			ls_validate_name "$user" && ls_validate_name "$host" || return 1
			ls_encrypt_asym "$pin" "$input" >"$dir/$user@$host.key" || return 1
		done
	fi
	ls_record_sign "$name" "$dir" || return 1
	ls_unlink "$plain" "$input"
}

function ls_secret_add { # NAME VALUE PUBKEY? ENCKEY? FORMAT_VERSION?
	if [ -n "${2:-}" ]; then
		printf '%s' "$2" | ls_secret_write "$1" "${3:-}" "${4:-}" "${5:-}"
	else
		ls_secret_write "$1" "${3:-}" "${4:-}" "${5:-}" </dev/stdin
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
	ls_safe_path "$secret_path/secret.enc" || return 1
	if [ ! -f "$secret_path/secret.enc" ]; then
		return 1
	else
		echo "$secret_path"
	fi
}

# --
# Looks for the secret key for the given secret, decrypting it with the given
# private key.
function ls_secret_key { # SECRET PRIVKEY?
	local snapshot
	snapshot="$(mktemp -d "$LS_TEMP_DIR/record.XXXXXXXX")" || return 1
	ls_record_read "$1" "$snapshot" "${2:-}" || return 1
	printf '%s' "$LS_RECORD_KEY"
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

# Function: ls_secret_hmac_store PATH HMAC
# Atomically writes an HMAC signature to `PATH` with restrictive permissions.
function ls_secret_hmac_store { # PATH HMAC
	local path="$1"
	local hmac="$2"
	local tmp
	[[ "$hmac" =~ ^(v2:etm:)?[A-F0-9]{64}$ ]] || return 1
	tmp="$(ls_mkstemp)" || return 1
	if ! printf '%s' "$hmac" >"$tmp"; then
		ls_unlink "$tmp"
		return 1
	fi
	ls_try_write "$tmp" "$path" true
}

# Function: ls_secret_hmac
# Calculates the HMAC for the given secret. If secret name is `-` then
# the secret is read from stdin.
function ls_secret_hmac { # SECRET_NAME SECRET_ENC_KEY?
	local secret_name="$1"
	local secret_key="${2:-}"
	if [ "$secret_name" == "-" ]; then
		[ -n "$secret_key" ] || return 1
		local mac_key
		mac_key="$(ls_secret_hmac_key "$secret_key")" || return 1
		[[ "$mac_key" =~ ^[a-f0-9]{64}$ ]] || return 1
		ls_hmac "$mac_key"
		return $?
	fi
	local snapshot
	snapshot="$(mktemp -d "$LS_TEMP_DIR/record.XXXXXXXX")" || return 1
	ls_record_read "$secret_name" "$snapshot" || return 1
	cat "$snapshot/secret.hmac"
}

# Function: ls_secret_hmac_ensure SECRET SECRET_KEY?
# Missing authentication data is never repaired implicitly.
function ls_secret_hmac_ensure { # SECRET SECRET_KEY?
	local secret_hmac_path
	secret_hmac_path="$(ls_secret_hmac_path "$1")" || return 1
	ls_safe_path "$secret_hmac_path" && [ -s "$secret_hmac_path" ]
}

function ls_secret_hmac_path { #SECRET
	local path
	path="$(ls_secret_path "$1")" || return 1
	printf '%s/secret.hmac\n' "$path"
}

# Function: ls_secret_format_version SECRET
# Returns 'v2' if the secret uses v2 Encrypt-then-MAC format, else 'v1'.
function ls_secret_format_version { # SECRET
	local secret="$1"
	local store
	store="$(ls_store)"
	if [ -z "$store" ] || ! ls_validate_name "$secret"; then
		return 1
	fi
	local hmac_path="$store/secret/$secret/secret.hmac"
	ls_safe_path "$hmac_path" || return 1
	local hmac
	hmac="$(cat "$hmac_path")" || return 1
	if [[ "$hmac" =~ ^v2:etm:[A-F0-9]{64}$ ]]; then
		printf '%s\n' v2
	elif [[ "$hmac" =~ ^[A-F0-9]{64}$ ]]; then
		printf '%s\n' v1
	else
		return 1
	fi
}

# Derives 256-bit encryption key and 256-bit authentication key from master key
function ls_secret_derive_keys_v2 { # MASTER_KEY
	local master_key="${1:-}"
	local sha512_hex
	if [ -z "$master_key" ]; then
		sha512_hex=$(ls_decode </dev/stdin | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha512 | cut -d' ' -f2) || return 1
	else
		sha512_hex=$(printf '%s' "$master_key" | ls_decode | "$LITTLESECRETS_OPENSSL_BIN" dgst -sha512 | cut -d' ' -f2) || return 1
	fi
	[[ "$sha512_hex" =~ ^[a-f0-9]{128}$ ]] || return 1
	# First 32 bytes (64 hex characters) = Encryption Key (K_enc)
	# Second 32 bytes (64 hex characters) = MAC Key (K_mac)
	printf '%s:%s\n' "${sha512_hex:0:64}" "${sha512_hex:64:64}"
}

# Computes v2 Encrypt-then-MAC HMAC over ciphertext file
function ls_secret_hmac_v2 { # SECRET_CIPHERTEXT_PATH MAC_KEY
	local enc_path="$1"
	local mac_key="$2"
	local mac_digest
	mac_digest=$(ls_hmac "$mac_key" "$enc_path") || return 1
	[[ "$mac_digest" =~ ^[A-F0-9]{64}$ ]] || return 1
	printf 'v2:etm:%s' "$mac_digest"
}

# Emits the JSON fields for a secret name/value pair.
function ls_json_emit_secret_value { # NAME VALUE INDENT?
	local tmp
	tmp="$(ls_mkstemp)" || return 1
	printf '%s' "$2" >"$tmp" || return 1
	ls_json_emit_secret_file "$1" "$tmp" "${3:-}" || return 1
	ls_unlink "$tmp"
}

function ls_json_emit_secret_file { # NAME PATH INDENT?
	local name="$1" tmp="$2" indent="${3:-}"
	local force_enc="${LITTLESECRETS_FORCE_ENCODING:-}"
	local is_binary=1
	if [ "$force_enc" = "base64" ]; then
		is_binary=0
	elif [ "$force_enc" = "text" ]; then
		ls_is_utf8_file "$tmp" || { ls_log_error "JSON text requires valid UTF-8: $name"; return 1; }
	elif ls_is_binary_file "$tmp"; then
		is_binary=0
	fi
	printf '%s"name": %s,\n' "$indent" "$(ls_json_string "$name")"
	if [ "$is_binary" -eq 0 ]; then
		local encoded_value
		encoded_value="$(ls_file_base64 "$tmp")" || return 1
		printf '%s"value": %s,\n' "$indent" "$(ls_json_string "$encoded_value")"
		printf '%s"encoding": "base64"' "$indent"
	else
		printf '%s"value": "' "$indent"
		LC_ALL=C od -An -v -tu1 "$tmp" | LC_ALL=C awk '
		{ for (i = 1; i <= NF; i++) {
			b = $i + 0
			if (b == 34) printf "\\\""
			else if (b == 92) printf "\\\\"
			else if (b < 32) printf "\\u%04x", b
			else printf "%c", b
		} }' || return 1
		printf '"'
	fi
}

# Emits JSON for a secret name/value pair. Handles binary detection & base64.
function ls_secret_emit_json { # NAME VALUE
	local fields
	fields="$(ls_json_emit_secret_value "$1" "$2" '  ')" || return 1
	printf '{\n%s\n}\n' "$fields"
}

function ls_secret_output { # NAME [PRIVATE_KEY]
	if [ "${LITTLESECRETS_FORMAT:-}" = json ]; then
		local tmp fields
		tmp="$(ls_mkstemp)" || return 1
		ls_secret_get "$1" "${2:-}" >"$tmp" || return 1
		fields="$(ls_json_emit_secret_file "$1" "$tmp" '  ')" || return 1
		printf '{\n%s\n}\n' "$fields" || return 1
		ls_unlink "$tmp"
	else
		ls_secret_get "$1" "${2:-}"
	fi
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
	local store
	store="$(ls_store)" || return 1
	if [ -e "$store/secret/$1" ] || [ -L "$store/secret/$1" ]; then
		ls_secret_migrate "$1" || return 1
	fi
	ls_record_transaction "$1" ls_secret_ensure_staged || return 1
	ls_secret_output "$1"
}

function ls_secret_ensure_staged { # NAME DIRECTORY
	if [ -e "$1" ]; then
		ls_record_copy "$1" "$2" || return 1
		ls_record_open "$1" "$2"
	else
		ls_log_action "ensure: Creating new random secret: $1"
		local random_secret
		random_secret=$("$LITTLESECRETS_OPENSSL_BIN" rand -base64 32 | tr -d '=+/\n' | cut -c1-16) || return 1
		[ "${#random_secret}" = 16 ] || return 1
		ls_user_register >/dev/null || return 1
		printf '%s' "$random_secret" | ls_secret_write_staged "$1" "$2" "" "" "${LITTLESECRETS_FORMAT_VERSION:-v2}"
	fi
}

function ls_secret_get { # NAME PRIVKEY?
	local snapshot
	ls_validate_name "$1" || return 1
	snapshot="$(mktemp -d "$LS_TEMP_DIR/record.XXXXXXXX")" || return 1
	ls_record_read "$1" "$snapshot" "${2:-}" || return 1
	ls_record_plaintext "$snapshot"
}

function ls_record_plaintext { # AUTHENTICATED_SNAPSHOT
	if [ "$LS_RECORD_FORMAT" = v1 ]; then
		cat "$LS_RECORD_PLAINTEXT"
	else
		local keys
		keys="$(ls_secret_derive_keys_v2 "$LS_RECORD_KEY")" || return 1
		local LITTLESECRETS_ALLOW_LEGACY=0
		ls_decrypt_sym "${keys%%:*}" <"$1/secret.enc"
	fi
}

# Function: ls_secret_verify
# Legacy records migrate before verification; signed records are read-only.
function ls_secret_verify { # NAME PRIVEY?
	ls_secret_get "$1" "${2:-}" >/dev/null
}

# Function: ls_secret_remove SECRET
# Removes *all* the files associated with the given secret, and clears the
# directory.
function ls_secret_remove() (
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret="$1"
	if ! ls_validate_name "$secret"; then
		ls_log_error "ls_secret_remove: Invalid secret name: $secret"
		return 1
	fi
	ls_safe_cd "$store/secret" || return 1
	LS_LOCK_PATHS=() LS_LOCK_TOKENS=()
	trap 'ls_lock_release ".$secret.lock.d"' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	ls_lock_acquire ".$secret.lock.d" || return 1
	ls_safe_path "$secret" || return 1
	rm -rf -- "$secret"
)

function ls_secret_grant { # SECRET USER_EXPR
	local secret_pattern="$1"
	shift
	local matching_secrets recipient_keys path pin secret
	local -a pins=()
	matching_secrets="$(ls_secret_list "$secret_pattern")" || return 1
	if [ -z "$matching_secrets" ]; then
		ls_log_warning "No secrets match pattern: $secret_pattern"
		return 1
	fi
	while IFS= read -r secret; do
		ls_secret_migrate "$secret" || return 1
	done <<<"$matching_secrets"
	recipient_keys="$(ls_user_key_paths "$@")" || return 1
	if [ -z "$recipient_keys" ]; then
		ls_log_error "User not found: $1"
		return 1
	fi
	while IFS= read -r path; do
		pin="$(ls_trusted_pubkey "$path")" || return 1
		pins+=("$pin")
	done <<<"$recipient_keys"
	ls_user_register >/dev/null || return 1
	while IFS= read -r secret; do
		ls_record_transaction "$secret" ls_secret_grant_staged "${pins[@]}" || return 1
	done <<<"$matching_secrets"
}

function ls_secret_grant_staged { # NAME DIRECTORY PINNED_KEYS...
	local name="$1" dir="$2" context input pin user host new_grant
	shift 2
	ls_record_copy "$name" "$dir" || return 1
	[ -f "$dir/secret.sig" ] || { ls_log_error "Upgrade legacy records before granting access"; return 1; }
	ls_record_open "$name" "$dir" || return 1
	context="$(ls_secret_context "$name")" || return 1
	input="$(ls_mkstemp)" || return 1
	printf 'LS3:%s:%s' "$context" "$LS_RECORD_KEY" >"$input" || return 1
	for pin in "$@"; do
		user="$(basename "$(dirname "$pin")")"; host="$(basename "$pin" .pubkey)"
		ls_validate_name "$user" && ls_validate_name "$host" || return 1
		new_grant=0
		[ -e "$dir/$user@$host.key" ] || new_grant=1
		ls_encrypt_asym "$pin" "$input" >"$dir/$user@$host.key" || return 1
		if [ "$new_grant" = 1 ]; then ls_log_action "Granted access to secret '$name' for '$user@$host'"; fi
	done
	ls_record_sign "$name" "$dir"
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
	local pattern="$1" secrets secret
	shift
	[ $# -gt 0 ] || return 1
	secrets="$(ls_secret_list "$pattern")" || return 1
	[ -n "$secrets" ] || return 1
	while IFS= read -r secret; do
		ls_secret_migrate "$secret" || return 1
	done <<<"$secrets"
	ls_user_register >/dev/null || return 1
	while IFS= read -r secret; do
		ls_record_transaction "$secret" ls_secret_rekey_staged revoke "$@" || return 1
	done <<<"$secrets"
}

function ls_secret_rekey_staged { # NAME DIRECTORY upgrade|revoke [USER_EXPR...]
	local name="$1" dir="$2" mode="$3" snapshot plain trust store file recipient user host pattern excluded pin registered
	shift 3
	local -a pins=()
	snapshot="$(mktemp -d "$LS_TEMP_DIR/record.XXXXXXXX")" || return 1
	ls_record_copy "$name" "$snapshot" || return 1
	if [ "$mode" = revoke ] && [ ! -f "$snapshot/secret.sig" ]; then
		ls_log_error "Upgrade legacy records before revoking access"
		return 1
	fi
	ls_record_open "$name" "$snapshot" || return 1
	plain="$(ls_mkstemp)" || return 1
	ls_record_plaintext "$snapshot" >"$plain" || return 1
	store="$(ls_store)" || return 1
	trust="$(ls_store_trust "$store")" || return 1
	for file in "$snapshot"/*.key; do
		recipient="$(basename "$file" .key)"
		user="${recipient%@*}"; host="${recipient#*@}"
		ls_validate_name "$user" && ls_validate_name "$host" || return 1
		excluded=0
		for pattern in "$@"; do
			if [[ "$pattern" == *@* ]]; then
				ls_match "$recipient" "$pattern" >/dev/null && excluded=1
			else
				ls_match "$user" "$pattern" >/dev/null && excluded=1
			fi
		done
		[ "$excluded" = 0 ] || continue
		pin="$trust/user/$user/$host.pubkey"
		ls_safe_path "$pin" || return 1
		if [ ! -f "$pin" ] && [ ! -f "$snapshot/secret.sig" ]; then
			# Legacy migration trusts recipient registrations in the accepted checkout.
			registered="$store/user/$user/$host.pubkey"
			ls_safe_path "$registered" || return 1
			[ -f "$registered" ] || { ls_log_error "Missing registered public key for legacy recipient: $recipient"; return 1; }
			ls_user_register "$recipient" "$registered" >/dev/null || return 1
		fi
		ls_safe_path "$pin" && [ -f "$pin" ] || { ls_log_error "Missing local recipient pin: $recipient; register its independently verified public key and retry"; return 1; }
		pins+=("$pin")
	done
	[ ${#pins[@]} -gt 0 ] || { ls_log_error "Cannot revoke the last recipient; remove the secret instead"; return 1; }
	ls_secret_write_staged "$name" "$dir" "" "" v2 "${pins[@]}" <"$plain"
}

function ls_secret_upgrade { # SECRET_EXPR...
	local store secrets
	store="$(ls_store)" || return 1
	secrets="$(ls_secret_list "$@")" || return 1
	if [ -z "$secrets" ]; then
		ls_log_message "No secrets found to upgrade"
		[ $# -eq 0 ]
		return $?
	fi
	local secret
	local upgraded_count=0
	while IFS= read -r secret; do
		local ver
		ver="$(ls_secret_format_version "$secret")" || return 1
		if [ ! -e "$store/secret/$secret/secret.sig" ] &&
			[ ! -e "$store/secret/$secret/secret.format" ] && [ ! -e "$store/secret/$secret/secret.signer" ]; then
			ls_secret_migrate "$secret" || return 1
			printf 'Upgraded: %s (%s -> signed v2)\n' "$secret" "$ver"
			upgraded_count=$((upgraded_count + 1))
			continue
		fi
		if [ "$ver" = "v2" ] && [ -f "$store/secret/$secret/secret.sig" ]; then
			ls_secret_verify "$secret" || return 1
			ls_log_message "Secret '$secret' is already format v2 (Encrypt-then-MAC)"
			echo "Already v2: $secret"
			continue
		fi
		ls_log_action "Upgrading secret '$secret' to format v2..."
		ls_user_register >/dev/null || return 1
		if ! ls_record_transaction "$secret" ls_secret_rekey_staged upgrade; then
			ls_log_error "Failed to write v2 secret for '$secret'"
			return 1
		fi
		ls_log_message "Upgraded '$secret' to format v2"
		printf 'Upgraded: %s (%s -> signed v2)\n' "$secret" "$ver"
		upgraded_count=$((upgraded_count + 1))
	done <<<"$secrets"
	ls_log_message "Upgrade complete: $upgraded_count secret(s) upgraded"
	return 0
}

function ls_user_deregister() ( # USER KEY?
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
	local given=""
	if [ -n "$key" ]; then given="$(ls_pubkey_import "$key")" || return 1; fi
	ls_safe_cd "$store/user/$user" || return 1
	local key_path
	local key_paths=()
	if [[ "$user_input" == *@* ]]; then
		key_paths=("$host.pubkey")
	else
		for key_path in ./*.pubkey; do
			if [ -e "$key_path" ]; then
				key_paths+=("$key_path")
			fi
		done
	fi
	if [ -n "$key" ]; then
		for key_path in "${key_paths[@]}"; do
			if [ -e "$key_path" ] && cmp -s "$key_path" <(printf '%s\n' "$given"); then
				rm -f -- "$key_path" || return 1
				return 0
			fi
		done
		return 1
	fi
	if [ "${#key_paths[@]}" -eq 0 ]; then return 1; fi
	rm -f -- "${key_paths[@]}"
)

function ls_secret_export {
	local output
	output="$(ls_mkstemp)" || return 1
	if ! ls_secret_export_stream "$@" >"$output"; then
		ls_unlink "$output"
		return 1
	fi
	cat "$output" || return 1
	ls_unlink "$output"
}

function ls_secret_export_stream {
	local listed var secname envname secval tmp escaped_val first=1
	local -a entries=("$@")
	if [ $# -eq 0 ]; then
		listed="$(ls_secret_list)" || return 1
		while IFS= read -r secname; do
			[ -z "$secname" ] || entries+=("$secname")
		done <<<"$listed"
	fi
	if [ "${LITTLESECRETS_FORMAT:-}" = json ]; then printf '[\n'; fi
	for var in "${entries[@]}"; do
		secname="${var##*=}"
		ls_validate_name "$secname" || return 1
		tmp="$(ls_mkstemp)" || return 1
		ls_secret_get "$secname" >"$tmp" || return 1
		if [ "${LITTLESECRETS_FORMAT:-}" = json ]; then
			if [ "$first" = 0 ]; then printf ',\n'; fi
			first=0
			printf '  {\n'
			ls_json_emit_secret_file "$secname" "$tmp" '    ' || return 1
			printf '\n  }'
		else
			envname="${var%%=*}"
			if [ "$envname" = "$secname" ]; then
				envname="$(printf '%s' "${envname//[.-]/_}" | tr '[:lower:]' '[:upper:]')" || return 1
			fi
			[[ "$envname" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { ls_log_error "Invalid environment variable name: $envname"; return 1; }
			if ! cmp -s "$tmp" <(tr -d '\000' <"$tmp"); then
				ls_log_error "Shell variables cannot contain NUL bytes; use JSON export: $secname"
				return 1
			fi
			secval="$(cat "$tmp" && printf '.')" || return 1
			secval="${secval%.}"
			escaped_val="${secval//\'/\'\\\'\'}"
			printf "export %s='%s'\n" "$envname" "$escaped_val"
		fi
		ls_unlink "$tmp"
	done
	if [ "${LITTLESECRETS_FORMAT:-}" = json ]; then printf '\n]\n'; fi
}

# Function: ls_secret_export_json_object [SECRET_NAME]
# Helper function to output a single secret as JSON object for export
function ls_secret_export_json_object {
	local tmp
	tmp="$(ls_mkstemp)" || return 1
	ls_secret_get "$1" >"$tmp" || return 1
	printf '  {\n'
	ls_json_emit_secret_file "$1" "$tmp" '    ' || return 1
	printf '\n  }'
	ls_unlink "$tmp"
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
	abs_path="$(ls_realpath "$store")"

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
		if [ "$(ls_realpath "$repository")" != "$abs_path" ]; then
			repositories+="$(ls_realpath "$repository") "
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
				printf '%s: %s\n' "$secret_name" "$(ls_realpath "$repository")"
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
	echo "Version: $LITTLESECRETS_VERSION"
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
	printf '  %-25s  %s\n' '--v1' 'Use signed v1 records (plaintext HMAC)'
	printf '  %-25s  %s\n' '--v2' 'Use signed, identity-bound v2 records (default)'
	printf '  %-25s  %s\n' '--allow-legacy' 'Compatibility option; legacy migration is automatic'
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
		--v1)
			LITTLESECRETS_FORMAT_VERSION="v1"
			shift
			;;
		--v2)
			LITTLESECRETS_FORMAT_VERSION="v2"
			shift
			;;
		--allow-legacy)
			LITTLESECRETS_ALLOW_LEGACY=1
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

		else
			ls_secret_output "$1" "${2:-}"
			return $?
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
					ls_secret_output "$1" || return 1
				fi
				return 0
			else
				return $?
			fi
		else
			# Read content from stdin
			if ls_secret_add "$1" "" "${2:-}" "${3:-}" >/dev/null; then
				if [ "${LITTLESECRETS_FORMAT:-}" = "json" ]; then
					ls_secret_output "$1" || return 1
				fi
				return 0
			else
				return $?
			fi
		fi
		;;
	## Integrity: hash [SECRET_EXPR...]  Print authenticated HMACs
	"hash")
		local secret secrets hmac
		secrets="$(ls_secret_list "$@")" || return 1
		[ $# -eq 0 ] || [ -n "$secrets" ] || return 1
		while IFS= read -r secret; do
			[ -n "$secret" ] || continue
			hmac="$(ls_secret_hmac "$secret")" || return 1
			printf '%s: %s\n' "$secret" "$hmac"
		done <<<"$secrets"
		;;
	## Integrity: verify [SECRET_EXPR...]  Verify signatures and HMACs; migrate legacy records
	"verify")
		local secret_name secrets result=0
		secrets="$(ls_secret_list "$@")" || return 1
		[ $# -eq 0 ] || [ -n "$secrets" ] || return 1
		while IFS= read -r secret_name; do
			[ -n "$secret_name" ] || continue
			ls_log_progress "Verifying $secret_name"
			ls_secret_verify "$secret_name" || result=1
		done <<<"$secrets"
		return "$result"
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
	## Secrets: upgrade [SECRET_EXPR...]  Migrate verified records to signed v2
	"upgrade")
		ls_secret_upgrade "$@"
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
trap ls_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
LS_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/littlesecrets.XXXXXXXX")" || exit 1

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	ls_cli "$@"
else
	# We only register error handling in library mode
	LS_TRAP_ERROR_PREVIOUS="$(ls_trap_extract ERR)"
	trap ls_on_error ERR
fi

# EOF
