--
Id: SEC-18
Title: Unquoted Expansions and Word Splitting Across CLI Handlers (LOW)
Location: src/sh/littlesecrets.sh:2326, 2420, 2442, 2582, 2604, 1972
--

Multiple CLI commands iterate over command substitutions without quoting:
for SECRET in $(ls_secret_list "$@"); do
- Impact:
If a secret name contains spaces, tabs, or wildcard characters (*, ?, []), Bash performs word splitting and filename pathname expansion, leading to misidentified or fragmented secret names.
- Remediation:
Read command output using line-oriented constructs such as `while IFS= read -r secret; do ... done < <(ls_secret_list "$@")` or `mapfile -t`.
