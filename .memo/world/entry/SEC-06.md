--
Id: SEC-06
Title: Missing Authenticated Encryption & Decrypt-before-Verify Malleability (HIGH)
Location: src/sh/littlesecrets.sh:1709–1747, 1749–1770
--

The script uses AES-256-CBC with PKCS#7 padding without Authenticated Encryption (AEAD). The HMAC is calculated over the decrypted plaintext and stored in a separate file (secret.hmac). In ls_secret_verify, the secret is decrypted before the HMAC is checked.
- Impact:
Decrypting unauthenticated ciphertext before validating authenticity violates the cryptographic principle of Authenticated Encryption, leaving the system vulnerable to padding oracle attacks and CBC bit-flipping attacks.
- Remediation:
Adopt an Authenticated Encryption mode (such as AES-256-GCM) or follow the Encrypt-then-MAC (EtM) paradigm where the HMAC covers the ciphertext and IV and is verified prior to decryption.
