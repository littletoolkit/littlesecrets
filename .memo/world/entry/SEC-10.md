--
Id: SEC-10
Title: Insecure File Permissions: Missing umask (HIGH)
Location: src/sh/littlesecrets.sh:1420, 685–690
--

The script never configures `umask 077`.
1. ls_try_write writes destination files via `cat "$path_tmp" > "$path_dst"`, creating new files using the environment's default umask (typically 0022 -> permissions 0644).
2. secret.enc, secret.hmac, and *.key files are created world-readable.
3. ls_privkey_new generates 4096-bit RSA private keys using `openssl genrsa -out "$1"`, which also creates world-readable files without chmod.
- Impact:
On multi-user systems, shared servers, or containers, any local user can read encrypted secrets, recipient access keys, and newly generated RSA private keys.
- Remediation:
Set `umask 077` at the beginning of littlesecrets.sh, and ensure sensitive files (keys, encrypted secrets) are explicitly created with permissions 0600 or 0400.
