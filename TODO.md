Fix:
- Ensure that when creating a secret, the HMAC is created as well

Test:
- SSH key passphrase protection workflow

Security Must:
- Tempfile should be stored encrypted, overwritten and removed on exit.
- Offer key rotation
- Encrypt-then-MAC with independent keys
- openssl dgst -sha256 -hmac "$1" leaks $1 (the secret key) in ps / /proc/<pid>/cmdline to any local user.

Security should:
- Ensure no private key is leaked/stored

Caveats:
- Compromised shell
- Revocation: ensure that revoke is followed by default by a rotation

User:
- Has no SSH keys
- Has a different username
- Has a different SSH key
- Is giving keypair through env vars
