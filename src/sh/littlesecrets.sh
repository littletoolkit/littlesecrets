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

# --
# We define the main internal variables
declare -a LS_CLEANUP=()
LS_CLEANUP+=("")

# --
# And define the configuration
LITTLESECRETS_USER=${LITTLESECRETS_USER:-$USER}
LITTLESECRETS_HOST=${LITTLESECRETS_HOST:-$HOSTNAME}
LITTLESECRETS_KEY=${LITTLESECRETS_KEY:-$HOME/.ssh/id_rsa}
LITTLESECRETS_STORE_NAME=".littlesecrets"
LITTLESECRETS_STORE=${LITTLESECRETS_STORE:-$LITTLESECRETS_STORE_NAME}
LITTLESECRETS_KEYSIZE=${LITTLESECRETS_KEYSIZE:-2048} # NOTE: It would be best to do 4096, and we should test keys
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
if [ -z "${NOCOLOR:-}" ] && [ -n "${TERM:-}" ] && tput setaf 1 &>/dev/null; then
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
LS_LOG_FILTER="warning tip"

function ls_log {
	if [[ "$LS_LOG_FILTER" = *"log"* ]]; then
		echo "${LS_LOG_PREFIX}$*${RESET}" >&2
	fi
}

function ls_log_action {
	if [[ "$LS_LOG_FILTER" = *"action"* ]]; then
		ls_log "${DIM}${BOLD} → ACT $*" >&2
	fi
	return 0
}

function ls_log_message {
	if [[ "$LS_LOG_FILTER" = *"message"* ]]; then
		ls_log "${DIM} … NFO $*"
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
		echo -n "$1" | ls_decode >"$res"
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

function ls_mkparent {
	for path in "$@"; do
		local parent
		parent="$(dirname "$path")"
		if [ -z "$parent" ]; then
			parent=
		elif [ ! -e "$parent" ]; then
			mkdir -p "$parent"
		fi
	done
}

function ls_ispath {
	if [[ "$1" != "${1/$'\n'/}" ]]; then
		return 1
	elif [ -e "$1" ]; then
		return 0
	else
		return 1
	fi
}

function ls_unlink {
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
	for path in "${LS_CLEANUP[@]}"; do
		if [ -z "$path" ]; then
			# nothing
			path=
		elif [ -e "$path" ]; then
			unlink "$path"
		fi
	done
	if [ -n "${LS_TRAP_PREVIOUS}" ]; then
		eval "$LS_TRAP_PREVIOUS"
	fi
}

function ls_ispath { ## PATHLIKE
	if [[ "${1:-}" =~ / ]] || [[ "${1:-}" != @LS:* ]]; then
		return 0
	else
		return 1
	fi
}

# --
# Echoes `TEXT` if any `EXPR` (glob) matches `TEXT`
function ls_match { # TEXT EXPR…
	local text="$1"
	shift # Remove first argument, leaving only the patterns
	if [ "$#" == 0 ]; then
		echo "$text"
		return 0
	else
		# FIXME: This does not seem to work with globs
		for pattern in "$@"; do
			# NOTE: Unquoting is on purpose
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
# VALUE ENCRYPTION
#
# -----------------------------------------------------------------------------
# This is to make sure we

# Generate a random 256-bit encryption key when the script starts
LS_VALUE_ENCRYPTION_KEY=$(openssl rand -hex 32)
LS_VALUE_ENCRYPTION_IV="00000000000000000000000000000000"

# Function: ls_value_encrypt [STDIN] [STDOUT]
# Function to encrypt stdin to stdout using the key
function ls_value_encrypt() {
	if [[ -z "$LS_VALUE_ENCKEY" ]]; then
		ls_log_error "LS_VALUE_ENCKEY not set"
		return 1
	fi
	# Use AES-256-CBC for encryption
	# -e: encrypt
	# -aes-256-cbc: cipher algorithm
	# -K: hex key
	# -iv: initialization vector (using fixed IV for simplicity, but you could generate random)
	# -nosalt: don't use salt (for consistency)
	openssl enc -e -aes-256-cbc \
		-K "$LS_VALUE_ENCRYPTION_KEY" \
		-iv "$LS_VALUE_ENCRYPTION_IV" \
		-nosalt 2>/dev/null || return 1
}

# Function: ls_value_decrypt [STDIN] [STDOUT]
# Function to decrypt stdin to stdout using the key
function ls_value_decrypt() {
	if [[ -z "$LS_VALUE_ENCKEY" ]]; then
		ls_log_error "LS_VALUE_ENCKEY not set"
		return 1
	fi
	openssl enc -d -aes-256-cbc \
		-K "$LS_VALUE_ENCRYPTION_KEY" \
		-iv "$LS_VALUE_ENCRYPTION_IV" \
		-nosalt 2>/dev/null || return 1
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
	local privkey_pem_path="${privkey_path}.pem"
	local pubkey_pem_path="${privkey_path}.pem.pub"
	# Ensures private key exists, otherwise creates it
	if [ ! -e "$privkey_path" ]; then
		ls_log_message "Missing SSH RSA key: $privkey_path"
		ls_log_action "Creating SSH key using 'ssh-keygen -t rsa -b 4096'"
		ls_log_output_start
		ssh-keygen -q -t rsa -b 4096 -N "" -f "$privkey_path" >&2
		ls_log_output_end
	fi
	ssh-keygen -y -P "" -f "$privkey_path" >/dev/null 2>&1
	if [ ! $? -eq 0 ]; then
		ls_log_error "SSH private key has a passphrase: $privkey_path"
		ls_log_tip "Generate a new key and set 'LITTLESECRETS_KEY' to that key"
		return 1
	fi
	# Ensures PEM private key exists, and is up to date
	if [ ! -e "$privkey_pem_path" ] || [ "$privkey_path" -nt "$privkey_pem_path" ]; then
		ls_log_action "Converting SSH RSA DER key to PEM format: $privkey_pem_path"
		# NOTE: ssh-keygen will overwrite the key, so we copy it
		cp -a "$privkey_path" "$privkey_pem_path.ssh"
		# SSH key is in DER format, we need PEM
		ls_log_output_start
		ssh-keygen -q -p -m pem -N '' -f "${privkey_pem_path}.ssh" >&2
		openssl rsa -in "${privkey_pem_path}.ssh" -out "${privkey_pem_path}" >&2
		ls_log_output_end
		unlink "${privkey_pem_path}.ssh"
	fi
	# Ensures PEM public key exists, and is up to date
	if [ ! -e "$pubkey_pem_path" ] || [ "$privkey_pem_path" -nt "$pubkey_pem_path" ]; then
		ls_log_action "Deriving PKCS8 public key from RSA PEM private key: $pubkey_pem_path"
		ls_log_output_start
		openssl rsa -in "$privkey_pem_path" -pubout -out "$pubkey_pem_path" >&2
		ls_log_output_end
	fi
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
	openssl genrsa -out "${1:-/dev/stdout}" 4096
}

# --
# Imports the private key at the given file, outputting the normalized key value.
# Will always return the private key as a its contents, not as a file.
function ls_privkey_import { # KEYPATH
	local keypath="${1:-$(ls_pubkey_path)}"
	local keyfmt=
	local keypath_tmp=
	local keyout_tmp=
	if ls_ispath "$1" && [ -e "$1" ]; then
		keyfmt="$(ls_key_id "$keypath")"
	else
		keypath_tmp="$(ls_mkstemp)"
		echo -n "$keypath" | ls_decode >"$keypath_tmp"
		keypath="$keypath_tmp"
		keyfmt="$(ls_key_id "$keypath")"
	fi
	local res=0
	case "$keyfmt" in
	# We obviously only support private keys here
	private:ssh*)
		keyout_tmp=$(ls_mkstemp)
		if ls_ispath "$keypath"; then
			cp -a "$keypath" "$keyout_tmp"
		else
			echo "$keypath" >"$keyout_tmp"
		fi
		ls_log_output_start
		ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" >&2
		ls_log_output_end
		openssl rsa -in "$keyout_tmp" -out /dev/stdout
		unlink "$keyout_tmp"
		;;
	private:pkcs8*)
		# That's what we want
		cat "$keypath"
		;;
	*)
		ls_log_error "ls_privkey_import: Unsupported format $keyfmt"
		;;
	esac
	ls_unlink "$keypath_tmp" "$keyout_tmp"
}

# --
# Imports the key at the given file, outputting the normalized key value.
function ls_pubkey_import { #KEYPATH
	local keypath="${1:-$(ls_pubkey_path)}"
	local keyfmt=
	local keypath_tmp=
	local keyout_tmp=
	if ls_ispath "$1" && [ -e "$1" ]; then
		keyfmt="$(ls_key_id "$keypath")"
	else
		keypath_tmp="$(ls_mkstemp)"
		echo -n "$keypath" | ls_decode >"$keypath_tmp"
		keypath="$keypath_tmp"
		keyfmt="$(ls_key_id "$keypath")"
	fi
	local res=0
	case "$keyfmt" in
	private:ssh*)
		keyout_tmp=$(ls_mkstemp)
		cp -a "$keypath" "${keyout_tmp}"
		ls_log_output_start
		if ! ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" >&2; then
			res=$?
		else
			openssl rsa -in "$keyout_tmp" -pubout
			res=$?
		fi
		ls_log_output_end
		unlink "$keyout_tmp"
		;;
	private:pkcs8*)
		openssl rsa -in "$keypath" -pubout
		res=$?
		;;
	public:ssh+rsa*)
		ssh-keygen -f "$keypath" -e -m PKCS8
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
function ls_key_id {
	# Function to analyze a single file
	local file="${1:-}"
	local tmp_file=""
	if [ -z "$file" ]; then
		tmp_file="$(ls_mkstemp)"
		cat /dev/stdin >"$tmp_file"
		file="$tmp_file"
	fi

	# Skip if not a regular file
	if [ ! -f "$file" ]; then
		echo "!nofile=$file"
		return 1
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
	if command -v openssl >/dev/null 2>&1; then
		if openssl rsa -in "$file" -noout 2>/dev/null; then
			echo ":valid=rsa"
		elif openssl ec -in "$file" -noout 2>/dev/null; then
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

function ls_encoded {
	case "$1" in
	@LS:*)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# --
# Safely encodes binary data to be stored in a variable
function ls_encode {
	echo -n "@LS:"
	openssl base64 -A </dev/stdin
}

# --
# Decoding version of `ls_encode`.
function ls_decode {
	local prefix
	read -n4 prefix
	if [ "$prefix" == "@LS:" ]; then
		openssl base64 -d -A </dev/stdin
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
	openssl rand "${1:-$ks}" | ls_encode
}

# --
function ls_encrypt_sym { # KEY
	local key_path=$(ls_mkstemp "$1")
	ls_log_output_start
	if ! {
		# NOTE: The fd anonymises the key path
		exec 3<"$key_path"
		openssl aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out /dev/stdout -pass fd:3
		local openssl_res=$?
		exec 3<&-
		return $openssl_res
	}; then
		ls_log_error "ls_encrypt_sym: Could not encrypt secret"
	fi
	ls_log_output_end
	unlink "$key_path"
}

# Function: ls_hmac KEY
# Calculates the hmac value of the given secret, typically used with the
# secret key.
# - Should be in hex (xxd) format
# - Key will be leaked to /proc, so should not be a secret
# - Use `ls_hmac_key` to pre-process your key
function ls_hmac {
	ls_log_output_start
	local key="${1:-}"
	key="${key//[[:space:]]/}" # Trim whitespace
	if [ -z "$key" ]; then
		ls_log_error "ls_hmac: Given key is empty"
		return 1
	elif ! openssl mac -macopt hexkey:"$key" -digest sha256 hmac | cut -d' ' -f2; then

		ls_log_error "ls_hmac: Could not generate secret HMAC"
	fi
	ls_log_output_end
}

# --
# Decrypts `1:SECRET` (encoded) with `2:KEY` (encoded), returning the
# decrypted secrets (unencoded)
function ls_decrypt_sym { # KEY
	local res=0
	local key_path=$(ls_mkstemp "$1")
	if ! {
		exec 3<"$key_path"
		openssl aes-256-cbc -md sha512 -salt -pbkdf2 -d -in /dev/stdin -out /dev/stdout -pass fd:3
		local openssl_res=$?
		exec 3<&-
		return $openssl_res
	}; then
		res=1
		ls_log_error "ls_decrypt_sym: Could not symmetrically decrypt secret [$res]"
	fi
	ls_log_output_end
	unlink "$key_path"
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
	if ! openssl pkeyutl -encrypt -pubin -inkey "$pubkey_path" -in "${secret_path}" -out /dev/stdout; then
		res=1
		ls_log_error "ls_encrypt_asym: Could not asymmetrically encrypt secret"
	fi
	ls_log_output_end
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
	if ! openssl pkeyutl -decrypt -inkey "$privkey_path" -in "$secret_path" -out /dev/stdout; then
		ls_log_error "ls_decrypt_asym: Could not asymmetrically decrypt secret [$?]"
		res=1
	fi
	ls_log_output_end
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

function ls_user_registered { # USER? KEY?
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user="$(ls_user_name "${1:-}")"
	local host="$(ls_user_host "${1:-}" "${2:-}")"
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
	local store="$(ls_store_ensure)"
	local user="$(ls_user_name "${1:-}")"
	local host="$(ls_user_host "${1:-}" "${2:-$LITTLESECRETS_KEY}")"
	local key="$(ls_pubkey_import "${2:-$LITTLESECRETS_KEY}")"
	local user_key_path="$store/user/$user/$host.pubkey"
	if [ -z "$key" ]; then
		ls_log_error "Could not import user public key: $(ls_pubkey_path "${1:-}" "${2:-}")"
		return 1
	fi
	if [ -e "$user_key_path" ]; then
		if ! cmp -s "$user_key_path" <(echo "$key"); then
			# We're overriding a key
			# TODO: We should probably warn here that the previous secrets
			# will likely be invalidated
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
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user="$(ls_user_name "${1:-}")"
	local host="${2:-}"
	if [ -n "$host" ]; then
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

# --
# Tries to extract the user@host from the given key.
function ls_pubkey_meta { # KEY
	local key="${1:-}"
	local fmt="$(ls_key_id "$key")"

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
		local meta="$(ls_pubkey_meta "$key")"
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
		local meta="$(ls_pubkey_meta "$key")"
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
		echo "$2" | sha256sum
		ls_pubkey_import "${2:-$LITTLESECRETS_KEY}"
	else
		# If not KEY is given, we look for a user.
		local user="$(ls_user_name "${1:-}")"
		local host="$(ls_user_host "${1:-}")"
		local store="$(ls_store)"
		if [ -n "$store" ]; then
			# If there's a store and the userkey exist, we return it.
			local keypath="$(ls_store)/user/$user/$host.pubkey"
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
	local keypath="${1:-$LITTLESECRETS_KEY}"
	local keypath_fmt=$(ls_key_id "$keypath")
	local keypath_pem="$keypath.pem"
	local keypath_pem_fmt=$(ls_key_id "$keypath_pem")
	if [[ "$keypath_fmt" == private:*pkcs8* ]]; then
		# The given keypath is already in the right format
		echo "$keypath"
	elif [[ "$keypath_pem_fmt" == private:*pkcs8* ]]; then
		# TODO: We should issue a warning if the PEM file is older than than the key
		# The alternate keypath is in the right formt
		echo "$keypath_pem"
	else
		if [ -e "$keypath" ]; then
			ls_log_action "ls_user_privkey: Importing private key to PKCS8/PEM format at $keypath"
		else
			ls_log_action "ls_user_privkey: Importing private key to PKCS8/PEM format"
		fi
		ls_privkey_import "$keypath"
	fi
}

# =============================================================================
# SECRETS
# =============================================================================

function ls_secret_list {
	local secrets
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
	local secret_path
	secret_path="$(ls_store)/secret/$secret_name/secret.enc"
	local secret_hmac_path
	secret_hmac_path="$(ls_store)/secret/$secret_name/secret.hmac"
	local has_hmac
	has_hmac="$(ls_option hmac)"
	# This creates the secret key, if it is not given.
	# NOTE that the key is ls_encoded.
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
	local user
	user=$(ls_user_name "${2:-}")
	local host
	host=$(ls_user_host "${2:-}")
	if [ -z "$store" ]; then return 1; fi
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
	secret_key_path="$(ls_secret_key_path "$1")"
	if [ "$?" != 0 ]; then
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
	if [ -z "${1:-}" ]; then
		ls_decode </dev/stdin | openssl dgst -sha256 -binary | xxd -p -c 64
	else
		printf '%s' "$1" | ls_decode | openssl dgst -sha256 -binary | xxd -p -c 64
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
}

function ls_secret_hmac_path { #SECRET
	echo "$(ls_secret_path "$1")/secret.hmac"
}

function ls_secret_ensure { # NAME
	if [ -z "${1:-}" ]; then
		ls_log_error "ensure: Missing secret name"
		return 1
	fi
	# Check if secret already exists (check the path, not access)
	if ls_secret_path "$1" >/dev/null 2>&1; then
		# Secret exists, check if user has access by trying to get the secret
		# We redirect stderr to avoid showing error messages during the check
		if ! ls_secret_get "$1" >/dev/null 2>&1; then
			ls_log_error "ensure: Secret '$1' exists but you don't have access to it"
			return 1
		fi
		# Secret exists and user has access, return success
		return 0
	else
		# Secret doesn't exist, create a new random secret (16 ASCII chars)
		ls_log_action "ensure: Creating new random secret: $1"
		local random_secret
		# Generate 16 random ASCII characters (alphanumeric)
		# Use more base64 data to ensure we get 16 chars after filtering
		random_secret=$(openssl rand -base64 20 | tr -d '=+/' | tr -d '\\n' | cut -c1-16)
		if [ -z "$random_secret" ]; then
			ls_log_error "ensure: Failed to generate random secret"
			return 1
		fi
		ls_secret_add "$1" "$random_secret"
		return $?
	fi
}

function ls_secret_get { # NAME PRIVKEY?
	# We locate the secret
	local secret="$1"
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
	local secret
	if secret="$(ls_decrypt_sym "$secret_key" <"$secret_path")"; then
		echo -n "$secret"
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
	# There is no hmac, so we can't verify but return a 0
	if [ -n "$(ls_option hmac)" ] && [ ! -e "$secret_hmac_path" ]; then
		ls_log_warning "No hmac found for secret $1: $secret_hmac_path"
		ls_log_tip "You can remove 'hmac' form LITTLESECRETS_OPTIONS to skip HMAC verification"
		return 0
	fi
	local hmac
	if ! hmac="$(ls_secret_hmac "$1" "$(ls_secret_key "$1" "${2:-}")")"; then
		ls_log_error "Could not compute HMAC for secret $1"
		return 1
	elif [ "$(cat "$secret_hmac_path")" != "$hmac" ]; then
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
	local secret_path="$store/secret/$1"
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

	# Process each matching secret
	for secret in "${matching_secrets[@]}"; do
		local secret_key
		secret_key=$(ls_secret_key "$secret")
		if [ "$?" != 0 ]; then
			ls_log_warning "Could not retrieve key for secret: $secret"
			continue
		fi

		ls_log_message "Granting access to secret: $secret"

		for user_expr in "$@"; do
			local user="${user_expr%@*}"

			if [[ "$user_expr" == *@* ]]; then
				# If user@host format, grant only to that specific host
				local host="${user_expr#*@}"
				local user_pubkey
				user_pubkey=$(ls_user_pubkey "$user_expr")
				if [ -n "$user_pubkey" ]; then
					local secret_key_path="$store/secret/$secret/$user@$host.key"
					ls_encrypt_asym "$user_pubkey" <(echo "$secret_key") >"$secret_key_path"
				fi
			else
				# Otherwise grant to all host keys for the user
				for pubkey_path in $(ls_user_list_keys "$user"); do
					local key_host
					key_host=$(basename "$pubkey_path" .pubkey)
					local secret_key_path="$store/secret/$secret/$user@$key_host.key"
					ls_encrypt_asym "$pubkey_path" <(echo "$secret_key") >"$secret_key_path"
				done
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
	shift
	for user_expr in "$@"; do
		local user
		user=$(ls_user_name "$user_expr")
		local host
		host=$(ls_user_host "$user_expr")

		if [[ "$user_expr" == *@* ]]; then
			# If user@host format, revoke only from that specific host
			local secret_key_path="$store/secret/$secret/$user@$host.key"
			if [ -e "$secret_key_path" ]; then
				rm -f "$secret_key_path"
			fi
		else
			# Otherwise revoke from all host keys for the user
			rm -f "$store/secret/$secret/$user@*.key"
		fi
	done
}

function ls_user_deregister { # USER KEY?
	local store
	store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user="$1"
	local key="${2:-}"
	if [ -n "$key" ]; then
		# Only remove if key matches
		local current
		current=$(ls_user_pubkey "$user")
		local given
		given=$(ls_pubkey_import "$key")
		if [ "$current" = "$given" ]; then
			rm -f "$store/user/$user.pubkey"
			return 0
		fi
		return 1
	else
		# Remove all keys
		rm -f "$store/user/$user.pubkey"
		return 0
	fi
}

function ls_secret_export {
	# This exports as a shell script, but we could export to other formats if
	# necessary.
	if [ $# -eq 0 ]; then
		local secrets
		secrets=$(ls_secret_list)
		if [ -z "$secrets" ]; then
			echo "# No secrets in $(ls_store)"
		else
			# We do want to split this and pass it as arguments
			# shellcheck disable=SC2068
			ls_secret_export ${secrets[@]}
		fi
	else
		local envname
		local secname
		local secval
		for var in "$@"; do
			envname="${var%%=*}"
			secname="${var##*=}"
			if [ "$envname" == "$secname" ]; then
				envname="$(echo "${envname//./_}" | tr 'a-z' 'A-Z')"
			fi

			if ! ls_secret_verify "$secname"; then
				ls_log_error "Could not validate secret authentiticy: $secname"
				echo "# Unable to validate secret authenticity: $secname"
			elif ! secval=$(ls_secret_get "$secname"); then
				ls_log_error "Unable to retrieve secret: $secname"
				echo "# Unable to retrieve secret: $secname"
			else
				# NOTE: Newlines are actually OK
				echo "export $envname='${secval}'"
			fi
		done
	fi
}

# -----------------------------------------------------------------------------
#
# CLI
#
# -----------------------------------------------------------------------------

function ls_cli {
	# Define version
	local VERSION="1.0.0"

	# Parse global options first

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-k | --key)
			LITTLESECRETS_KEY="$2"
			shift 2
			;;
		-u | --user)
			LITTLESECRETS_USER="$2"
			shift 2
			;;
		--host)
			LITTLESECRETS_HOST="$2"
			shift 2
			;;
		-s | --store)
			LITTLESECRETS_STORE="$2"
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

	case "$cmd" in
	## help              Show this help message
	"help" | h)
		echo "Usage: littlesecrets [options] <command> [args...]"
		echo ""
		echo "Options:"
		echo "  -h, --help        Show this help message"
		echo "  -v, --version     Show version information"
		echo "  -k, --key KEY     Set private key path"
		echo "  -u, --user USER   Set user name"
		echo "  --host HOST       Set host name (default: \$HOSTNAME)"
		echo "  -s, --store PATH  Set store path"
		echo ""
		echo "Commands:"
		grep '^[[:space:]]##[[:space:]]' "$0" | sed 's/^[[:space:]]*##[[:space:]]//'
		return 0
		;;
	## version           Show version information
	"version" | v)
		echo "littlesecrets version $VERSION"
		return 0
		;;
	## init [path]        Initialize a new secrets store
	"init")
		ls_store_init "${1:-.}"
		;;
	## list|ls [expr...]  List secrets matching expr
	"list" | "ls")
		for SECRET in $(ls_secret_list "$@"); do
			echo "${BOLD}$SECRET${RESET}: ${DIM}$(ls_secret_keys "$SECRET")${RESET}"
		done
		;;
	## get <name>         Get a secret's value
	"get")
		if [ -z "${1:-}" ]; then
			ls_log_error "get: Missing secret name"
			return 1
		elif ! ls_secret_path "$1" >/dev/null; then
			ls_log_error "Secret does not exist: $1"
			# TODO: Should find approximate matches
			return 1

		elif [ -n "$(ls_option hmac)" ] && ! ls_secret_verify "$1"; then
			ls_log_error "Secret signature differs: $1"
			ls_log_tip "Secret likely has been updated and your key is out of date"
			return 1
		else
			ls_secret_get "$1" "${2:-}"
			return $?
		fi
		;;
	## add|set <name> [value] Set a secret's value
	"add" | "set")
		if [ -z "${1:-}" ]; then
			ls_log_error "add: Missing secret name"
			return 1
		fi
		if [ -n "${2:-}" ]; then
			# Content provided as argument
			ls_secret_add "$1" "$2" "${3:-}" "${4:-}"
			return $?
		else
			# Read content from stdin
			ls_secret_add "$1" "" "${2:-}" "${3:-}"
			return $?
		fi
		;;
	## hash NAMES* Ensures the secrets habe a matching hash
	"hash")
		for SECRET in $(ls_secret_list "$@"); do
			SECRET="${SECRET%%:*}"
			HMAC_PATH="$(ls_secret_hmac_path "$SECRET")"
			HMAC="$(ls_secret_hmac "$SECRET")"
			if [ ! -e "$HMAC_PATH" ]; then
				ls_log_action "Creating HMAC for secret $SECRET at $HMAC_PATH"
				echo -n "$HMAC" >"$HMAC_PATH"
			elif [ "$(cat "$HMAC_PATH")" != "$HMAC" ]; then
				ls_log_warning "Existing HMAC differs for secret $SECRET, updating."
				echo -n "$HMAC" >"$HMAC_PATH"
			fi
		done
		;;
	## verify NAMES* Verifies the decrypted secret against the hash
	"verify")
		created=()
		valid=()
		invalid=()
		nokey=()
		for SECRET_NAME in $(ls_secret_list "$@"); do
			SECRET_NAME="${SECRET_NAME%%:*}"
			HMAC_PATH="$(ls_secret_hmac_path "$SECRET_NAME")"
			echo -n "Verifying $SECRET_NAME… "
			if [ ! -e "$HMAC_PATH" ]; then
				# NOTE: Leaving this for reference
				if HMAC=$(ls_secret_hmac "$SECRET_NAME"); then
					echo "${GREEN}CREATED${RESET}"
					ls_log_action "Creating HMAC signature for secret: $SECRET_NAME"
					echo -n "$HMAC" >"$HMAC_PATH"
					created+=("$SECRET_NAME")
				else
					nokey+=("$SECRET_NAME")
					echo "${ORANGE}no hash${RESET}"
				fi
			elif [ "$(cat "$HMAC_PATH")" != "$(ls_secret_hmac "$SECRET_NAME")" ]; then
				ls_log_warning "Existing HMAC differs for secret $SECRET_NAME"
				ls_log_tip "Most likely the original secret has changed and you haven't been granted the key."
				invalid+=("$SECRET_NAME")
				echo "${RED}INVALID${RESET}"
			else
				valid+=("$SECRET_NAME")
				echo "${GREEN}OK${RESET}"
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
	## remove <name>      Remove a secret
	"remove")
		if [ -z "${1:-}" ]; then
			ls_log_error "remove: Missing secret name"
			return 1
		fi
		ls_secret_remove "$1"
		return $?
		;;
	## grant <name> <expr...> Grant access to users matching expr
	"grant")
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
	## revoke <name> <expr...> Revoke access from users matching expr
	"revoke")
		if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
			ls_log_error "revoke: Missing secret name or user pattern"
			return 1
		fi
		ls_secret_revoke "$1" "$2"
		return $?
		;;
	## register [user] [key] Register a user's public key
	"register")
		ls_user_register "${1:-}" "${2:-}"
		return $?
		;;
	## deregister <user> [key] De-register a user's public key
	"deregister")
		if [ -z "${1:-}" ]; then
			ls_log_error "deregister: Missing user"
			return 1
		fi
		ls_user_deregister "$1" "${2:-}"
		return $?
		;;
	## users [expr...]    List users matching expr
	"users")
		ls_user_list "$@"
		return $?
		;;
	## access [expr...]   List users with access to secrets matching expr
	"access")
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
		;;
	## export [VAR=secret...]   Exports the given secrets as variables
	"export")
		ls_secret_export "$@"
		return $?
		;;
	## ensure <name>      Ensure a secret exists (create if missing)
	"ensure")
		ls_secret_ensure "$@"
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

LS_TRAP_PREVIOUS="$(trap -p EXIT INT TERM | cut -d"'" -f2 | sort | uniq)"
LS_TRAP_ERROR_PREVIOUS=""
trap ls_cleanup EXIT INT TERM

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	ls_cli "$@"
else
	# We only register error handling in library mode
	LS_TRAP_ERROR_PREVIOUS="$(trap -p ERR | cut -d"'" -f2 | sort | uniq)"
	trap ls_on_error ERR
fi

# EOF
