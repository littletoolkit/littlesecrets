--
Id: SEC-12
Title: Secret Revocation Does Not Rotate Cryptographic Keys (MEDIUM)
Location: src/sh/littlesecrets.sh:1871–1889
--

function ls_secret_revoke removes the recipient's $user@$host.key file, but does not re-encrypt secret.enc with a fresh symmetric key.
- Impact:
A revoked user who previously decrypted the secret or retained the symmetric key can still decrypt the secret from Git history, backups, or existing copies of secret.enc.
- Remediation:
Document that revocation only stops new key distribution, or implement key rotation on revocation (re-encrypting the secret with a newly generated symmetric key and re-encrypting it only for remaining authorized recipients).
