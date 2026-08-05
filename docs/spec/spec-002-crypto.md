# Cryptography

The core cryptography works as such:

- Users register their SSH (RSA) public key in the shared secrets.
- A secret is encrypted using a randomly generated key, which is kept secret, and then stored.
- Before being stored, the key will be encrypted with the user's registered SSH (RSA) public key.
- The user can grant other user's access to the secret by decrypting the secret's encryption key,
  and encrypting it with the other user's SSH public key.
- A secret can be revoked by removing the encrypted secret, or re-encrypting it.
- A secret can have an associated HMAC signature using the decrypted secret as the
  message and the secret encryption key in base64 as the key. This ensures integrity.

Note that:

- Users may have multiple SSH keys associated with their name, for instance, when using different computer.
- Users may have on a given machine multiple SSH keypairs, using different formats, like RSA or ECDSA.

In practice:

- Secrets are symmetrically encrypted using AES-256-CBC and a random key. Its
  maximum length is derived from `LITTLESECRETS_KEYSIZE`, which defaults to
  2048 for RSA-OAEP payload sizing.
- Secret encryption key is asymmetrically encrypted using an RSA keypair
- An RSA private key either in SSH or PEM (openssl) format
- An RSA public key in PEM (openssl) format, optional as it can be derived from the private key
- An secret encryption key no longer than what the RSA keypair can encrypt
- Generated SSH and OpenSSL RSA keys are 4096-bit.

Some considerations of this system:

- AES-256-CBC is used alongside HMAC in place of AES-256-GCM as the GCM version
  is not widely available using the `openssl` CLI, and we want to minimize dependencies.
- HMAC uses the encryption key in base64 format primarily due to shell implementation
  limitations, this has no effect on entropy.
- Secrets and key storage should be version controlled using a system like git, which
  then provides auditability.

In shell, the symmetric encryption works like so:

```
# Outputs an encryption key, no longer than what the RSA keypair can encrypt
openssl rand 214 # 2048/8 - 42

# Outputs the encrypted secret using the encryption key
openssl aes-256-cbc -md sha512 -salt -pbkdf2 -in /dev/stdin -out /dev/stdout -pass "file:$SECRET_ENC_KEY_PATH"

# Outputs the decrypted secret using the encryption key
openssl aes-256-cbc -md sha512 -salt -pbkdf2 -d -in /dev/stdin -out /dev/stdout -pass "file:$SECRET_ENC_KEY_PATH"
```

In shell, the management of RSA keys works like so:

```
# Create an SSH/RSA private key
ssh-keygen -q -t rsa -b 4096 -N "" -f "$PRIVATE_KEY_PATH"

# Convert (in place) an SSH/RSA private key to OpenSSL/RSA private key
ssh-keygen -q -p -m pem -N '' -f "$PRIVATE_KEY_PATH"

# Outputs an SSH/RSA public key to OpenSSL/RSA public key
ssh-keygen -e -m PKCS8 -f "$PUBLIC_KEY_PATH"

# Create an OpenSSL/RSA private key
openssl genrsa -out "$PRIVATE_KEY_PATH" 4096

# Outputs an OpenSSL/RSA public key from an OpenSSL/RSA private key
openssl rsa -in "$PRIVATE_KEY_PATH" -pubout
```

The asymmetric encryption works like so, where what is encrypted is the key
used to symmetrically encrypt the secret.

```
# Outputs the encrypted secret using the given OpenSSL/RSA public key
openssl pkeyutl -encrypt -pubin -inkey "$PUBLIC_KEY_PATH" -in "$SECRET_ENC_KEY_PATH" -out /dev/stdout

# Outputs the decrypted secret using the given OpenSSL/RSA private key
openssl pkeyutl -decrypt -inkey "$PRIVATE_KEY_PATH" -in "$SECRET_ENC_KEY_PATH" -out /dev/stdout
```

The HMAC integrity validation works using the decrypted *secret* and the
*secret encryption key*, both are binary data.

```
# Computes a base64 version of the encryption key so that it can be HMAC'ed
SECRET_HMAC_KEY="$(echo -n "$SECRET_ENC_KEY" | openssl base64 -A)"

# Computes the HMAC of the secret (decrypted) using the HMAC key.
# LittleSecrets uses the standard HMAC inner/outer-pad construction with
# `openssl dgst -sha256`, so the key is never passed in command arguments.
```

Note that in the shell based implementation we:
- Temporary files are set with strict modes (`600`) and are cleaned up
- Avoid passing secrets in the command arguments or in the environment, to ensure there's no leaking.
