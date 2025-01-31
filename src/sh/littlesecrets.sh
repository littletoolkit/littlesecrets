#!/usr/bin/env bash
#  _ _ _   _   _      __                    _
# | (_) |_| |_| | ___/ _\ ___  ___ _ __ ___| |_ ___
# | | | __| __| |/ _ \ \ / _ \/ __| '__/ _ \ __/ __|
# | | | |_| |_| |  __/\ \  __/ (__| | |  __/ |_\__ \
# |_|_|\__|\__|_|\___\__/\___|\___|_|  \___|\__|___/

# TODO: register, etc don't work well as pubkey is not imported properly

# --
# A simplified, reduced version of LittleSecrets that works only with
# the shell and simple tools.

set -euo pipefail
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
LITTLESECRETS_KEYSIZE=2048

# -----------------------------------------------------------------------------
#
# COLORS
#
# -----------------------------------------------------------------------------

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

function ls_log_action {
	echo " → $@" >&2
	return 0
}

function ls_log_message {
	echo " … $*" >&2
	return 0
}

function ls_log_tip {
	echo " ✱ $*" >&2
	return 0
}

function ls_log_error {
	echo "${RED}!!! ERR ${BOLD}$*${RESET}" >&2
	return 0
}

function ls_log_output_start {
	echo -n "${GRAY}" >&2
}

function ls_log_output_end {
	echo -n "${RESET}" >&2
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
			echo >&2 "${ORANGE} ▸  #${i} ${YELLOW}${BOLD}$func() ${RESET}$path:$line"
		fi
	done
}

function ls_on_error {
	echo >&2 "${RED} ⚠  ERR Command failed $?: !! ${RESET}"
	ls_log_stack
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
	local res=$(mktemp)
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
		local parent="$(dirname "$path")"
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
		for pattern in "$@"; do
			if [[ "$text" == $pattern ]]; then
				echo "$text"
				return 0
			fi
		done
		return 1
	fi
}

function ls_match_item {
	local store=$(ls_store)
	local item=
	local path="$1"
	shift
	if [ -n "$store" ]; then
		for item_path in ${store}/${path}; do
			item="$(basename "$(dirname "$item_path")")"
			if [ -n "$(ls_match "$item" "$@")" ]; then
				echo "$item"
			fi
		done
	else
		return 1
	fi
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
function ls_privkey_path { #KEYPATH
	ls_ssh_keypair_ensure "$@"
}

# --
# Returns the normalized public key path for the key at the given path
function ls_pubkey_path { #KEYPATH
	echo "$(ls_ssh_keypair_ensure "$@").pub"
}

function ls_privkey_new {
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
	if [ -e "$1" ]; then
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
	private:ssh:*)
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
		res=1
		;;
	esac
	ls_unlink "$keypath_tmp" "$keyout_tmp"
	return $res
}

# --
# Imports the key at the given file, outputting the normalized key value.
function ls_pubkey_import { #KEYPATH
	local keypath="${1:-$(ls_pubkey_path)}"
	local keyfmt=
	local keypath_tmp=
	local keyout_tmp=
	if [ -e "$1" ]; then
		keyfmt="$(ls_key_id "$keypath")"
	else
		keypath_tmp="$(ls_mkstemp)"
		echo -n "$keypath" | ls_decode >"$keypath_tmp"
		keypath="$keypath_tmp"
		keyfmt="$(ls_key_id "$keypath")"
	fi
	local res=0
	case "$keyfmt" in
	private:ssh:*)
		keyout_tmp=$(ls_mkstemp)
		cp -a "$keypath" "${keyout_tmp}"
		ls_log_output_start
		if ! ssh-keygen -q -p -m pem -N '' -f "$keyout_tmp" >&2; then
			res="$?"
		else
			openssl rsa -in "$keyout_tmp" -pubout
			res="$?"
		fi
		ls_log_output_end
		unlink "$keyout_tmp"
		;;
	private:pkcs8*)
		openssl rsa -in "$keypath" -pubout
		res="$?"
		;;
	public:ssh+rsa*)
		ssh-keygen -f "$keypath" -e -m PKCS8
		res="$?"
		;;
	public:spki*)
		cat "$keypath"
		;;
	*)
		res=1
		;;
	esac
	ls_unlink "$keypath_tmp" "$keyout_tmp"
	return $res
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
			local all_found=1
			IFS='+' read -ra required_formats <<<"$formats"
			for fmt in "${required_formats[@]}"; do
				if [[ "$text_format" != *"$fmt"* ]]; then
					return 1
				fi
			done
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
	local result=""

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

	# Restore original values
	LITTLESECRETS_KEY="$orig_key"
	LITTLESECRETS_USER="$orig_user"
	LITTLESECRETS_STORE="$orig_store"

	return $ret
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
	if ! openssl aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out /dev/stdout -pass "file:$key_path"; then
		ls_log_error "ls_encrypt_sym: Could not encrypt secret"
	fi
	ls_log_output_end
	unlink "$key_path"
}

# --
# Decrypts `1:SECRET` (encoded) with `2:KEY` (encoded), returning the
# decrypted secrets (unencoded)
function ls_decrypt_sym { # KEY
	local key_path=
	local res=0
	local key_path="$(ls_mkstemp "$1")"
	ls_log_output_start
	if ! openssl aes-256-cbc -md sha512 -salt -pbkdf2 -d -in /dev/stdin -out /dev/stdout -pass "file:$key_path"; then
		ls_log_error "ls_decrypt_sym: Could not decrypt secret"
		res=1
	fi
	ls_log_output_end
	ls_unlink "$key_path"
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
		ls_log_error "ls_encrypt_asym: Could not encrypt secret"
	fi
	ls_log_output_end
	if [ "$pubkey_temp" == 1 ]; then
		unlink "$pubkey_path"
	fi
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
		ls_log_error "ls_decrypt_asym: Could not decrypt secret"
	fi
	ls_log_output_end
	if [ "$privkey_temp" == 1 ]; then
		unlink "$privkey_path"
	fi
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
	echo "$(realpath "$parent/$LITTLESECRETS_STORE_NAME")"
}

# --
# Ensures that the store exists
function ls_store_ensure {
	local store=$(ls_store)
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
	ls_match_item "user/*/*.pubkey" "$@"
}

function ls_user_registered { # USER? KEY?
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user="$(ls_user_name "${1:-}")"
	local host="$(ls_user_host "${1:-}")"
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
	local host="$(ls_user_host "${1:-}")"
	local key="$(ls_pubkey_import "${2:-$LITTLESECRETS_KEY}")"
	local user_key_path="$store/user/$user/$host.pubkey"
	if [ -z "$key" ]; then
		ls_log_error "Could not import user public key: $(ls_pubkey_path "${1:-}" "${2:-}")"
		return 1
	fi
	echo "KEY: $key"
	if [ -e "$user_key_path" ]; then
		if [ ! cmd -s "$user_key_path" <(echo "$key") ]; then
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

function ls_user_name { # USER?
	local user="${1:-$LITTLESECRETS_USER}"
	# Extract username if in user@host format
	echo "${user%@*}"
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

function ls_user_host { # USER?
	local user="${1:-$LITTLESECRETS_USER}"
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
	if [[ "$keypath_fmt" == private:pkcs8* ]]; then
		# The given keypath is already in the right format
		echo "$keypath"
		return 0
	elif [[ "$keypath_pem_fmt" == private:pkcs8* ]]; then
		# TODO: We should issue a warning if the PEM file is older than than the key
		# The alternate keypath is in the right formt
		echo "$keypath_pem"
	else
		ls_privkey_import "$keypath"
	fi
}

# =============================================================================
# SECRETS
# =============================================================================

function ls_secret_list {
	ls_match_item "secret/*/secret.enc" "$@"
}

function ls_secret_write { # NAME PUBKEY? SECRETKEY?
	local secret="$1"
	local secret_path="$(ls_store)/secret/$secret/secret.enc"
	local secret_key="${3:-}"
	if [ -z "$secret_key" ]; then
		secret_key="$(ls_key)"
	fi
	# First step, we encrypt the secret with the secret key
	ls_mkparent "$secret_path"
	ls_encrypt_sym "$secret_key" </dev/stdin >"$secret_path"

	# Second step, encrypt the secret key for each of the user's host keys
	local user=$(ls_user_name)
	if [ -n "${2:-}" ]; then
		# If a specific pubkey is provided, use only that
		local user_pubkey=$(echo "${2:-}" | ls_decode)
		local secret_key_path="$(ls_store)/secret/$secret/$user.key"
		ls_encrypt_asym "$user_pubkey" <(echo "$secret_key") >"$secret_key_path"
	else
		# Otherwise encrypt for all host keys
		for pubkey_path in $(ls_user_list_keys "$user"); do
			local host=$(basename "$pubkey_path" .pubkey)
			local secret_key_path="$(ls_store)/secret/$secret/$user@$host.key"
			ls_encrypt_asym "$pubkey_path" <(echo "$secret_key") >"$secret_key_path"
		done
	fi
	echo "$secret_path"
}

function ls_secret_add { # SECRET CONTENT PUBKEY? ENCKEY?
	if [ -n "${2:-}" ]; then
		echo -n "$2" | ls_secret_write "$1" "${3:-}" "${4:-}"
	else
		ls_secret_write "$1" "${3:-}" "${4:-}" </dev/stdin
	fi
}

function ls_secret_key_path { # SECRET USER?
	local store="$(ls_store)"
	local user=$(ls_user_name)
	if [ -z "$store" ]; then return 1; fi
	local secret_key_path="$store/secret/$1/$user.key"
	if [ -e "$secret_key_path" ]; then
		echo "$secret_key_path"
	else
		return 1
	fi
}

function ls_secret_path { # SECRET
	# We locate the secret
	local secret="$1"
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret_path="$store/secret/$secret/secret.enc"
	if [ ! -e "$secret_path" ]; then
		return 1
	else
		echo "$secret_path"
	fi
}

function ls_secret_key { # SECRET PRIVKEY?
	local user_privkey=$(ls_user_privkey "${2:-}" | ls_decode)
	local secret_key_path="$(ls_secret_key_path "$1")"
	if [ "$?" != 0 ]; then
		return 1
	else
		ls_decrypt_asym "$user_privkey" <"$secret_key_path"
	fi
}

function ls_secret_get { # NAME PRIVKEY?
	# We locate the secret
	local secret="$1"
	local store="$(ls_store)"
	local secret_path="$store/secret/$secret/secret.enc"
	if [ ! -e "$secret_path" ]; then return 0; fi

	# First step, we decrypt the secret key with the user's private key
	local user=$(ls_user_name)
	local host=$(ls_user_host)
	local user_privkey=$(ls_user_privkey "${2:-}" | ls_decode)
	local secret_key_path="$store/secret/$secret/$user@$host.key"
	if [ ! -e "$secret_key_path" ]; then return 0; fi
	local secret_key=$(ls_decrypt_asym "$user_privkey" <"$secret_key_path")

	# Second step, we decrypt the secret with
	local secret
	secret="$(ls_decrypt_sym "$secret_key" <"$secret_path")"
	local res="$?"
	echo "$secret"
	return "$res"
}

function ls_secret_remove { # SECRET
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret_path="$store/secret/$1"
	if [ -e "$secret_path" ]; then
		rm -rf "$secret_path"
		return 0
	fi
	return 1
}

function ls_secret_grant { # SECRET USER_EXPR
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret="$1"
	shift
	local secret_key=$(ls_secret_key "$secret")
	if [ "$?" != 0 ]; then return 1; fi

	for user_expr in "$@"; do
		local user=$(ls_user_name "$user_expr")
		local host=$(ls_user_host "$user_expr")

		if [[ "$user_expr" == *@* ]]; then
			# If user@host format, grant only to that specific host
			local user_pubkey=$(ls_user_pubkey "$user_expr")
			if [ -n "$user_pubkey" ]; then
				local secret_key_path="$store/secret/$secret/$user@$host.key"
				ls_encrypt_asym "$user_pubkey" <(echo "$secret_key") >"$secret_key_path"
			fi
		else
			# Otherwise grant to all host keys for the user
			for pubkey_path in $(ls_user_list_keys "$user"); do
				local key_host=$(basename "$pubkey_path" .pubkey)
				local secret_key_path="$store/secret/$secret/$user@$key_host.key"
				ls_encrypt_asym "$pubkey_path" <(echo "$secret_key") >"$secret_key_path"
			done
		fi
	done
}

function ls_secret_users { # SECRET?
	local store="$(ls_store)"
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
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local secret="$1"
	shift
	for user_expr in "$@"; do
		local user=$(ls_user_name "$user_expr")
		local host=$(ls_user_host "$user_expr")

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
	local store="$(ls_store)"
	if [ -z "$store" ]; then return 1; fi
	local user="$1"
	local key="${2:-}"
	if [ -n "$key" ]; then
		# Only remove if key matches
		local current=$(ls_user_pubkey "$user")
		local given=$(ls_pubkey_import "$key")
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

# -----------------------------------------------------------------------------
#
# CLI
#
# -----------------------------------------------------------------------------

function ls_cli {
	# Define version
	local VERSION="1.0.0"

	# Parse global options first
	local orig_key="$LITTLESECRETS_KEY"
	local orig_user="$LITTLESECRETS_USER"
	local orig_host="$LITTLESECRETS_HOST"
	local orig_store="$LITTLESECRETS_STORE"

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
		-* | --*)
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

	# Handle the command
	local ret=0

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
		grep '^[[:space:]]*##' "$0" | sed 's/^[[:space:]]*## \?/  /g'
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
		ls_secret_list "$@"
		;;
	## get <name>         Get a secret's value
	"get")
		if [ -z "${1:-}" ]; then
			ls_log_error "get: Missing secret name"
			return 1
		fi
		ls_secret_get "$1" "${2:-}"
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
		else
			# Read content from stdin
			ls_secret_add "$1" "" "${2:-}" "${3:-}"
		fi
		;;
	## remove <name>      Remove a secret
	"remove")
		if [ -z "${1:-}" ]; then
			ls_log_error "remove: Missing secret name"
			return 1
		fi
		ls_secret_remove "$1"
		;;
	## grant <name> <expr...> Grant access to users matching expr
	"grant")
		if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
			ls_log_error "grant: Missing secret name or user pattern"
			return 1
		fi
		ls_secret_grant "$1" "$2"
		;;
	## revoke <name> <expr...> Revoke access from users matching expr
	"revoke")
		if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
			ls_log_error "revoke: Missing secret name or user pattern"
			return 1
		fi
		ls_secret_revoke "$1" "$2"
		;;
	## register [user] [key] Register a user's public key
	"register")
		ls_user_register "${1:-}" "${2:-}"
		;;
	## deregister <user> [key] De-register a user's public key
	"deregister")
		if [ -z "${1:-}" ]; then
			ls_log_error "deregister: Missing user"
			return 1
		fi
		ls_user_deregister "$1" "${2:-}"
		;;
	## users [expr...]    List users matching expr
	"users")
		ls_user_list "$@"
		;;
	## access [expr...]   List users with access to secrets matching expr
	"access")
		if [ -z "${1:-}" ]; then
			ls_secret_users
		else
			for secret in $(ls_secret_list "$@"); do
				echo -n "$secret:"
				ls_secret_users "$secret"
				echo
			done
		fi
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

trap ls_cleanup EXIT INT TERM

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	ls_cli "$@"
else
	# We only register error handling in library mode
	trap ls_on_error ERR
fi

# EOF
