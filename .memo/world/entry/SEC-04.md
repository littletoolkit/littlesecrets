--
Id: SEC-04
Title: Path Traversal in Secret Names, User Names, and Host Names (HIGH)
Location: src/sh/littlesecrets.sh:1177, 1436, 1476, 1904
--

User, host, and secret names are interpolated directly into filesystem paths without path traversal sanitization:
- user_key_path="$store/user/$user/$host.pubkey"
- secret_key_path="$(ls_store)/secret/$secret_name/$user@$host.key"
- secret_path="$(ls_store)/secret/$secret_name/secret.enc"
- key_paths=("$store/user/$user/$host.pubkey")
- Impact:
Supplying values containing / or ../ allows reading, creating, modifying, or deleting files outside the .littlesecrets/ directory hierarchy.
- Remediation:
Validate user, host, and secret names against a strict whitelist regex (e.g. ^[a-zA-Z0-9._-]+$) before using them in filesystem operations.
