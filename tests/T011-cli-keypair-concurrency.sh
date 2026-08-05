#!/usr/bin/env bash
# shellcheck disable=SC1091
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
for key_path in "${key_paths[@]}"; do
	for _ in {1..4}; do
	(
		# The sourced CLI must not invoke the test harness cleanup handler.
		trap - EXIT INT TERM ERR
		export LITTLESECRETS_KEY="$key_path"
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

test-end
