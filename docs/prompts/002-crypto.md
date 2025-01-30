# Cryptography

The core cryptography works as such:

- Users register their SSH public key in the shared secrets.
- A secret is encrypted using a randomly generated key, which is kept secret, and then stored.
- Before being stored, the key will be encrypted with the user's registered
  SSH public key.
- The user can grant other user's access to the secret by decrypting the secret's encryption key,
  and encrypting it with the other user's SSH public key.
- A secret can be revoked by removing the encrypted secret, or re-encrypting it.

Note that:

- Users may have multiple SSH keys associated with their name, for instance, when using different computer.
- Users may have on a given machine multiple SSH keypairs, using different formats, like RSA or ECDSA.

In practice:

- Secrets are symmetrically encrypted using a random key
- Secret encryption key is asymmetrically encrypted using an RSA keypair
- An RSA private key either in SSH or PEM (openssl) format
- An RSA public key in PEM (openssl) format, optional as it can be derived from the private key
- An secret encryption key no longer than what the RSA keypair can encrypt

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
