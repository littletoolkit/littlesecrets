Test:
- SSH key passphrase protection workflow

Security:
- Offer key rotation

Commands:
- Revocation: ensure that revoke is followed by default by a rotation

Caveats:
- Compromised shell

User:
- Has no SSH keys
- Has a different username
- Has a different SSH key
- Is giving keypair through env vars
