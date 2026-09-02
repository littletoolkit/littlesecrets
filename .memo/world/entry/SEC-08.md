--
Id: SEC-08
Title: Unauthenticated Public Key Overwrite / Identity Hijacking (HIGH)
Location: src/sh/littlesecrets.sh:1182–1194
--

In ls_user_register:
if [ -e "$user_key_path" ]; then
    if ! cmp -s "$user_key_path" <(echo "$key"); then
        echo "$key" >"$user_key_path"
    fi
An existing user's registered public key is replaced unconditionally without requiring any authentication, signature, or confirmation.
- Impact:
An attacker can overwrite another user's public key with their own public key. When other users run `littlesecrets grant`, the secret's encryption key will be encrypted with the attacker's public key, giving the attacker access.
- Remediation:
Refuse to overwrite an existing user public key unless an explicit flag (e.g. --force) is supplied, and log a prominent security warning.
