#!/usr/bin/env bash
LITTLESECRETS_LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LITTLESECRETS_LIB_MODULES=$(find "$LITTLESECRETS_LIB_PATH" -name "*.sh")
LITTLESECRETS_LIB_LOADED=
export LITTLESECRETS_LIB_MODULES

function ls_lib_load {
	local module_path=""
	for module in "$@"; do
		module_path=$LITTLESECRETS_LIB_PATH/$module.sh
		# Actually, following that advice breaks the code
		# shellcheck disable=SC2076
		if ! [[ "$LITTLESECRETS_LIB_LOADED" =~ "[$module]" ]]; then
			if [ -e "$module_path" ]; then
				LITTLESECRETS_LIB_LOADED+="[$module]"
				# shellcheck source=/dev/null
				source "$module_path"
			else
				>&2 echo "${RED:-} ⚠  ERR [lib] Module '$module' not found: ${ORANGE:-}$module_path${RESET:-}"
			fi
		fi
	done
}
# EOF
