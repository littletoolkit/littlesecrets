#!/bin/env/bash
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh
test-start
for TEST in $BASE/*.*; do
	case $TEST in
	*/lib-*.sh) ;;
	*/harness.sh) ;;
	*/*.sh)
		echo
		test-step "$TEST"
		if bash "$TEST"; then
			test-ok "Passed $TEST"
		else
			test-fail "Failed $TEST"
		fi
		;;
	esac
done

test-cleanup

# EOF
