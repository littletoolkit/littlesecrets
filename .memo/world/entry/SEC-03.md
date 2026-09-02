--
Id: SEC-03
Title: Symmetric Key Truncation & Weak Passphrase Handling in ls_encrypt_sym (CRITICAL)
Location: src/sh/littlesecrets.sh:933–938, 941–960, 1004–1025
--

ls_key generates 214 bytes of raw pseudo-random binary data (via openssl rand). When encrypting or decrypting, ls_mkstemp decodes these raw bytes into a file passed to:
openssl aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out "$output_path" -pass fd:3
OpenSSL's -pass parameter treats the input as a line-based passphrase string (using BIO_gets), terminating at the first newline byte (0x0A) or null byte (0x00).
- Impact:
1. In 214 random bytes, the probability of containing byte 0x0A is ~56.8%. The key is truncated at that byte, drastically reducing key entropy.
2. If the first byte is 0x0A (1 in 256 chance), OpenSSL reads an empty passphrase "", meaning the secret is encrypted with a blank password.
3. Using raw binary data as a passphrase string for PBKDF2 is cryptographically incorrect and unreliable.
- Remediation:
Hex-encode the symmetric key or generate a fixed-size 32-byte hex key, and pass it directly to openssl enc with -K and -iv, or ensure the passphrase contains no nulls or newlines.
