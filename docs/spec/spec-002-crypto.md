# Cryptography

LittleSecrets uses RSA keypairs for wrapping and signing, and AES-256-CBC with
PBKDF2 plus HMAC-SHA256 for secret values. Generated RSA keys are 4096-bit;
existing RSA keys should be at least 2048-bit. OpenSSH and OpenSSL RSA formats
are supported; passphrase-protected private keys are not.

## Master keys and encryption

Every newly written record gets 32 random master-key bytes, represented as
`@LS:` plus base64. Key size is independent of the RSA modulus; the historical
`LITTLESECRETS_KEYSIZE` setting is unused. Custom keys supplied through the shell
API must still fit the recipient's OAEP capacity together with the context.

For v2, SHA-512 of the decoded master key supplies two non-overlapping halves:
one encryption input and one HMAC key, represented as lowercase hex ASCII.
The encryption helper hex-encodes its input and supplies it via a file
descriptor to:

```sh
openssl aes-256-cbc -md sha512 -salt -pbkdf2 -pass fd:3
```

The HMAC covers the exact salted ciphertext and is verified before AES
decryption. The v1 scheme instead uses the master key for encryption and a
hex-ASCII SHA-256 digest of that key for the plaintext HMAC. Plaintext is held
privately until all required authentication succeeds.

The HMAC implementation uses the standard SHA-256 inner/outer-pad construction
without putting keys in external process arguments. Shell builtins and private
files handle key material. Supplying CLI values as arguments still exposes them
to process listings and shell history; prefer stdin.

## Recipient envelopes and signatures

Each recipient gets an RSA-encrypted envelope containing the master-key
representation and a context digest binding the store identity and secret name:

```sh
openssl pkeyutl -encrypt -pubin -inkey "$PUBLIC_KEY_PATH" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
  -in "$ENVELOPE_PATH" -out "$WRAPPED_KEY_PATH"
```

Records also carry an RSA/SHA-256 signature covering context, format, signer,
ciphertext, HMAC, and all recipient envelopes. Signing and verification use:

```sh
openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" -out "$SIGNATURE_PATH" "$PAYLOAD_PATH"
openssl dgst -sha256 -verify "$PINNED_PUBLIC_KEY_PATH" \
  -signature "$SIGNATURE_PATH" "$PAYLOAD_PATH"
```

The public key must come from the local trust database, not an unverified shared
registration. Signatures use RSA PKCS#1 v1.5 signature encoding; encryption uses
OAEP-SHA256. See `spec-011-format-v2.md` for exact byte framing and key encodings.

## Sharing and limits

Grant authenticates the source record before wrapping its key for pinned
recipients. Revoke rotates the master key and re-encrypts for the remaining
recipients. It cannot erase a former recipient's plaintext or historical keys;
external credentials must also be rotated at their source.

Authentication is mandatory. Missing tags are never regenerated. Unsigned
historical records migrate automatically on access, using historical RSA
padding and raw-passphrase fallbacks only while verifying the old HMAC.
Signed records never use those fallbacks. Missing signed metadata and an `LS3:`
envelope without its signature are errors, not legacy migration candidates.

Legacy migration authenticates the value before initializing local identity
and caller-key pins. Missing pins for other recipients are initialized from
public-key registrations in the accepted Git checkout; existing pins are retained.
Historical HMACs cannot authenticate names or recipient lists, so the initial
legacy checkout must be trusted. Migration cannot retroactively supply that
missing evidence.

The shell implementation uses private temporary files, owned locks, staged
writes, and verified snapshots. It trusts the local account, executables, and
trust database. Tag comparison uses `cmp -s` and has no constant-time guarantee.
Signatures do not detect replay of an old valid record; trusted version history
is needed to establish freshness. The CLI is not a network decryption service.
