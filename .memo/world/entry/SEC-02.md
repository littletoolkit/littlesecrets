--
Id: SEC-02
Title: Arbitrary Directory Deletion (rm -rf) via Path Traversal in Secret Removal (CRITICAL)
Location: src/sh/littlesecrets.sh:1775–1784
--

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
There is zero validation on $1 in ls_secret_remove or the remove CLI command.
- Impact:
If an attacker or malicious script passes ../../.. or ../../.git to `littlesecrets remove`, rm -rf "$store/secret/../../.." recursively deletes arbitrary directories, including the parent workspace or Git repository.
- Remediation:
Enforce strict validation on secret names across all functions:
if [[ ! "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    ls_log_error "Invalid secret name: $1"
    return 1
fi
