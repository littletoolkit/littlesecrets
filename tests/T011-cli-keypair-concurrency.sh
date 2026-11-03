#!/usr/bin/env bash
# Each child intentionally selects its own key before sourcing the CLI.
# shellcheck disable=SC1091,SC2030,SC2031
BASE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
source "$BASE/tests/lib-testing.sh"

test-start

test-step "Concurrent SSH key derivation"
key_path="$TEST_PATH/id_rsa"
ssh-keygen -q -t rsa -b 2048 -N "" -f "$key_path"
ln -s "$key_path" "$TEST_PATH/id_rsa.alias"

declare -a pids=()
key_paths=(
	"$key_path"
	"$TEST_PATH/./id_rsa"
	"$TEST_PATH/id_rsa.alias"
)
for key_candidate in "${key_paths[@]}"; do
	for _ in {1..4}; do
	(
		# The sourced CLI must not invoke the test harness cleanup handler.
		trap - EXIT INT TERM ERR
		export LITTLESECRETS_KEY="$key_candidate"
		export NOCOLOR=1
		source "$BASE/src/sh/littlesecrets.sh"
		ls_privkey_path
	) >/dev/null 2>&1 &
	pids+=("$!")
	done
done

failed=false
for pid in "${pids[@]}"; do
	if ! wait "$pid"; then
		failed=true
	fi
done
if [ "$failed" = true ]; then
	test-fail "Concurrent key derivation failed"
else
	test-ok "Concurrent key derivation succeeded"
fi

privkey_pem_paths=("$TEST_PATH"/littlesecrets-*.pem)
privkey_pem_path="${privkey_pem_paths[0]}"
pubkey_pem_path="${privkey_pem_path}.pub"
test-expect-success openssl rsa -in "$privkey_pem_path" -noout
test-expect-success openssl rsa -pubin -in "$pubkey_pem_path" -noout
test-expect "$(stat -c %a "$privkey_pem_path")" "400" "Private PEM permissions"
test-expect "$(stat -c %a "$pubkey_pem_path")" "400" "Public PEM permissions"

test-step "Fresh key derivation returns only paths"
ssh-keygen -q -t rsa -b 2048 -N "" -C "fresh@test" -f "$TEST_PATH/fresh_rsa"
privkey_path="$(
	trap - EXIT INT TERM ERR
	export LITTLESECRETS_KEY="$TEST_PATH/fresh_rsa"
	source "$BASE/src/sh/littlesecrets.sh"
	ls_privkey_path
)"
test-exist "$privkey_path"
pubkey_path="$(
	trap - EXIT INT TERM ERR
	export LITTLESECRETS_KEY="$TEST_PATH/fresh_rsa"
	source "$BASE/src/sh/littlesecrets.sh"
	ls_pubkey_path
)"
test-expect "$pubkey_path" "${privkey_path}.pub" "Public key path matches private key path"
test-exist "$pubkey_path"

test-end
