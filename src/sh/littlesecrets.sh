#!/usr/bin/env bash

# --
# A simplified, reduced version of LittleSecrets that works only with
# the shell and simple tools.

# --
# We load the library expected to be in `LITTLESECRETS_PATH`
LITTLESECRETS_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$LITTLESECRETS_PATH"/littlesecrets/lib.sh
ls_lib_load colors

# --
# We define the main internal variables
declare -a LS_CLEANUP=()
LS_CLEANUP+=("")

# --
# And define the configuration
LITTLESECRETS_SSH_KEY=${LITTLESECRETS_SSH_KEY:-$HOME/.ssh/id_rsa}

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
	echo "!!! ERR $*" &
	1>2
	return 0
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
			>&2 echo "${ORANGE} ▸  #${i} ${YELLOW}${BOLD}$func() ${RESET}$(fmt-relpath "$path"):$line"
		fi
	done
}

function ls_on_error {
	>&2 echo "${RED} ⚠  ERR Command failed${RESET}"
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

# -----------------------------------------------------------------------------
#
# KEYS
#
# -----------------------------------------------------------------------------

# --
# Ensures that the `LITTLESECRETS_SSH_KEY` exists and is in the right format.
function ls_ssh_keypair_ensure {
	local privkey_path="${1:-$LITTLESECRETS_SSH_KEY}"
	local privkey_pem_path="${privkey_path}.pem"
	local pubkey_pem_path="${privkey_path}.pem.pub"
	# Ensures private key exists, otherwise creates it
	if [ ! -e "$privkey_path" ]; then
		ls_log_message "Missing SSH RSA key: $privkey_path"
		ls_log_action "Creating SSH key using 'ssh-keygen -t rsa -b 4096'"
		ssh-keygen -q -t rsa -b 4096 -N "" -f "$privkey_path" >&2
	fi
	ssh-keygen -y -P "" -f "$privkey_path" >/dev/null 2>&1
	if [ ! $? -eq 0 ]; then
		ls_log_error "SSH private key has a passphrase: $privkey_path"
		ls_log_tip "Generate a new key and set 'LITTLESECRETS_SSH_KEY' to that key"
		return 1
	fi
	# Ensures PEM private key exists, and is up to date
	if [ ! -e "$privkey_pem_path" ] || [ "$privkey_path" -nt "$privkey_pem_path" ]; then
		ls_log_action "Converting SSH RSA DER key to PEM format: $privkey_pem_path"
		# NOTE: ssh-keygen will overwrite the key, so we copy it
		cp -a "$privkey_path" "$privkey_pem_path.ssh"
		# SSH key is in DER format, we need PEM
		ssh-keygen -q -p -m pem -N '' -f "${privkey_pem_path}.ssh" >&2
		openssl rsa -in "${privkey_pem_path}.ssh" -out "${privkey_pem_path}" >&2
		unlink "${privkey_pem_path}.ssh"
	fi
	# Ensures PEM public key exists, and is up to date
	if [ ! -e "$pubkey_pem_path" ] || [ "$privkey_pem_path" -nt "$pubkey_pem_path" ]; then
		ls_log_action "Deriving PKCS8 public key from RSA PEM private key: $pubkey_pem_path"
		openssl rsa -in "$privkey_pem_path" -pubout -out "$pubkey_pem_path" >&2
	fi
	echo "${privkey_pem_path}"
}

function ls_privkey {
	ls_ssh_keypair_ensure
}

function ls_pubkey {
	echo "$(ls_ssh_keypair_ensure).pub"
}

# --
# Outputs the type/format of the key, in `:` separated form
# 1) Key type, `public` or `private` or `unknown`
# 2) Key format, `+` separated, like `pkcs8+rsa`
# 3) `valid` if the format was validated, otherwise nothing
function ls_keyid {
	# Function to analyze a single file
	local file="${1:-}"
	if [ -z "$file" ]; then
		file="$(cat /dev/stdin)"
	fi
	local result=""

	# Skip if not a regular file
	[ ! -f "$file" ] && return

	# Check if file is binary or text
	if file "$file" | grep -q "ASCII text"; then
		# Check for SSH public key format
		if grep -q "^ssh-" "$file" 2>/dev/null; then
			if grep -q "ssh-rsa" "$file"; then
				echo -n "public:ssh+rsa"
			elif grep -q "ecdsa-sha2" "$file"; then
				echo -n "public:ssh+ecdsa"
			fi
		# Check for PEM format
		elif grep -q "BEGIN" "$file" 2>/dev/null; then
			if grep -q "BEGIN RSA PRIVATE KEY" "$file"; then
				echo -n "private:rsa+pem+pkcs1"
			elif grep -q "BEGIN EC PRIVATE KEY" "$file"; then
				echo -n "private:ecdsa+pem+sec1"
			elif grep -q "BEGIN PRIVATE KEY" "$file"; then
				echo -n "private:pkcs8"
			elif grep -q "BEGIN PUBLIC KEY" "$file"; then
				echo -n "public:spki"
			elif grep -q "BEGIN OPENSSH PRIVATE KEY" "$file"; then
				echo -n "private:ssh"
			fi
		fi

		# Additional OpenSSL analysis
		if command -v openssl >/dev/null 2>&1; then
			if openssl rsa -in "$file" -noout 2>/dev/null; then
				echo "+rsa:valid"
			elif openssl ec -in "$file" -noout 2>/dev/null; then
				echo "+ecdsa:valid"
			fi
		else
			echo ":"
		fi
	else
		echo "unknown"
	fi
}

# -----------------------------------------------------------------------------
#
# CRYPTO
#
# -----------------------------------------------------------------------------

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
function ls_key_sym {
	# RSA 4096bits -> 512bytes
	# PKCS requires 11bytes padding, OAEP 42bytes
	openssl rand "${1:-470}" | ls_encode
}

# --
# Encrypts `1:SECRET` (encoded) with `2:KEY` (encoded), returning the
# encrypted secrets (encoded)
function ls_encrypt_sym {
	local secret="$1"
	local key_path=$(ls_mkstemp "$2")
	echo -n "$secret" | ls_decode | openssl aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out /dev/stdout -pass "file:$key_path" | ls_encode
	unlink "$key_path"
}

# --
# Decrypts `1:SECRET` (encoded) with `2:KEY` (encoded), returning the
# decrypted secrets (unencoded)
function ls_decrypt_sym {
	local encrypted="$1"
	local key_path="$(ls_mkstemp "$2")"
	if ! echo -n "$encrypted" | ls_decode | openssl aes-256-cbc -md sha512 -salt -pbkdf2 -d -in /dev/stdin -out /dev/stdout -pass "file:$key_path"; then
		ls_log_error "Could not decrypt secret"
	else
		unlink "$key_path"
	fi

}

# --
# Encrypts the given secret using the given public key. When the key is empty
# it will be sourced using `ls_pubkey`, otherwise it can be given either
# as a path, or as a value (encoded or not). This returns the encrypted secret,
# encoded.
function ls_encrypt_asym {
	local secret="$1"
	local pubkey="${2:-}"
	local pubkey_path
	local pubkey_temp=0
	if [ -z "$pubkey" ]; then
		pubkey_path="$(ls_pubkey)"
	elif [ -e "$pubkey" ]; then
		pubkey_path="$pubkey"
	else
		pubkey_path="$(ls_mkstemp "$pubkey")"
		pubkey_temp=1
	fi
	if ! echo -n "$secret" | ls_decode | openssl pkeyutl -encrypt -pubin -inkey "$pubkey_path" -in /dev/stdin -out /dev/stdout | ls_encode; then
		ls_log_error "Could not encrypt secret"
	fi
	if [ "$pubkey_temp" == 1 ]; then
		unlink "$pubkey_path"
	fi
}

# --
# Decrypts the given encrypted secret using the given private key. When the key is empty
# it will be sourced using `ls_privkey`, otherwise it can be given either
# as a path, or as a value (encoded or not). This returns the decypted secret, unencoded.
function ls_decrypt_asym {
	local encrypted="$1"
	local privkey="${2:-}"
	local privkey_path
	local privkey_temp=0
	if [ -z "$privkey" ]; then
		privkey_path="$(ls_privkey)"
	elif [ -e "$privkey" ]; then
		privkey_path="$privkey"
	else
		privkey_path="$(ls_mkstemp "$privkey")"
		privkey_temp=1
	fi
	if ! echo -n "$encrypted" | ls_decode | openssl pkeyutl -decrypt -inkey "$privkey_path" -in /dev/stdin -out /dev/stdout; then
		ls_log_error "Could not decrypt secret"
	fi
	if [ "$privkey_temp" == 1 ]; then
		unlink "$pubkey_path"
	fi
}

trap ls_cleanup EXIT INT TERM
trap ls_on_error ERR

# EOF
