# Signed Records, Format v2, and Migration

## Record layout

Both newly written v1 and v2 records use the signed record-3 envelope. The
`v1`/`v2` value identifies the symmetric encryption/HMAC scheme, not whether a
record is signed. Older clients cannot consume the new recipient envelopes.

```
.littlesecrets/store.id                  # 32 lowercase hex characters + LF
.littlesecrets/secret/<name>/
  secret.format                        # v1 or v2, no trailing LF
  secret.signer                        # user@host, no trailing LF
  secret.enc                           # OpenSSL salted AES-CBC ciphertext
  secret.hmac                          # Mandatory authentication tag
  secret.sig                           # Binary RSA/SHA-256 signature
  <user>@<host>.key                     # Binary RSA-OAEP-SHA256 envelope
```

## Identity and signature

`init` generates a 16-byte random store identity and pins it outside the shared
store. The record context is the lowercase hexadecimal SHA-256 digest of:

```
ASCII("LittleSecrets record 3") || NUL || ASCII(store.id without LF) || NUL
    || ASCII(secret name) || NUL
```

Recipient envelopes encrypt the exact ASCII string:

```
LS3:<64-character context hash>:<master-key representation>
```

The default master-key representation is `@LS:` followed by base64 of 32 random
bytes. RSA encryption uses `pkeyutl` with `rsa_padding_mode:oaep` and
`rsa_oaep_md:sha256` (MGF1 uses the same digest).

The signed payload starts with `LittleSecrets record 3:<context hash>\n`.
It then includes these files in order:

1. `secret.format`
2. `secret.signer`
3. `secret.hmac`
4. `secret.enc`
5. All recipient `*.key` files, sorted using the C locale

Each field is framed as `<basename>:<decimal byte length>\n` followed by the
exact file bytes, with no extra separator. Names are validated filesystem
components. The signature excludes `secret.sig` itself and is produced with
`openssl dgst -sha256 -sign`, using RSA's PKCS#1 v1.5 signature encoding.
This signature padding is distinct from the OAEP encryption padding.

Verification uses the signer's independently pinned local public key, never an
unverified key from the shared store. The signature covers every recipient
envelope, preventing envelope swaps and recipient changes by an untrusted store
editor. The context prevents moving a valid record to another secret name or
store identity. Reads also require the decrypted envelope's context to match.

## Symmetric schemes

Let `K` be the decoded master-key bytes. Hash outputs below are lowercase hex
ASCII strings unless otherwise stated.

| Property | v1 | v2 (default) |
|---|---|---|
| Encryption input key | `K` | First 64 hex characters of `SHA512(K)` |
| HMAC key | 64 hex characters of `SHA256(K)` | Last 64 hex characters of `SHA512(K)` |
| HMAC target | Exact plaintext bytes | Exact `secret.enc` bytes |
| Tag | 64 uppercase hex characters | `v2:etm:` + 64 uppercase hex characters |

The encryption helper converts its input key bytes to lowercase hex ASCII and
passes that string via a file descriptor to
`openssl aes-256-cbc -md sha512 -salt -pbkdf2`. In v2 this deliberately means
hex-encoding the ASCII encryption-key substring, preserving the existing v2
cipher convention. HMAC keys are used as ASCII bytes, not decoded from hex.
Tags have no trailing newline.

The HMAC implementation uses SHA-256's standard inner/outer-pad construction
without placing the key in external process arguments. The default master key
contains 256 random bits; its size is independent of RSA key size.

## Read pipeline

Authenticated access first checks for a genuine unsigned legacy record and
migrates it using the procedure below. Signed records then follow this pipeline:

1. Take a per-secret lock and copy the record into a private snapshot.
2. Check the locally pinned store identity and signer key.
3. Verify the signature, including format metadata and all recipient envelopes.
4. Decrypt the caller's recipient envelope and check its context.
5. For v2, verify the ciphertext HMAC before AES decryption. For v1, decrypt
   privately and verify the plaintext HMAC before returning any bytes.
6. Return plaintext from the authenticated snapshot, not a reopened store file.

Missing, empty, malformed, or invalid authentication data is fatal. No read,
`hash`, `verify`, or `export` operation repairs it. Automatic migration only
rewrites records after their existing HMAC verifies. `LITTLESECRETS_OPTIONS` cannot
disable verification. Tag comparison uses `cmp -s`, which is **not** claimed to
be constant-time. This is a local CLI, not a remotely exposed decryption oracle.

Signatures establish authenticity under a local pin, not freshness: replaying
an older valid record remains possible. Names, recipients, and store listings
are visible metadata. There is no authenticated store-wide manifest.

## Writes, grants, and revocation

`add`/`set` creates a fresh master key, ciphertext, tag, recipient envelopes, and
signature in a staging directory. A per-secret lock covers staging and
publication; the previous record is retained for rollback on ordinary failure.
`ensure` checks existence under the same lock and refuses damaged records.

`grant` authenticates the existing record before rewrapping its key. Recipient
public keys must match local pins. It then signs the entire updated record.

`revoke` enumerates actual recipient envelopes, including deregistered users.
It authenticates the old record, creates a fresh master key, and re-encrypts as
v2 for every remaining pinned recipient. Missing pins fail the whole update;
recipients are never silently dropped. The last recipient cannot be revoked.
Key rotation cannot erase plaintext or keys already copied by former recipients.

See `spec-004-store.md` for locking, trust storage, and recovery limits.

## Automatic migration

Historical unsigned v1/v2 records migrate on authenticated access through `get`,
`ensure`, `hash`, `verify`, `export`, `grant`, and `revoke`, and through the shell
key/HMAC accessors. `upgrade` offers eager migration. The `--allow-legacy` flag
remains accepted for compatibility but is unnecessary for these commands.

A genuine legacy record has none of `secret.sig`, `secret.format`, or
`secret.signer`, and its decrypted envelope must not start with `LS3:`. A signed
record with a deleted signature or stripped metadata is rejected rather than
automatically re-signed. Signed records never enable legacy decryption fallbacks.

Migration:

1. Takes a private snapshot and verifies the existing HMAC using the caller's
   private key. Historical PKCS#1 v1.5 encryption padding and raw-passphrase
   fallbacks are available only on this legacy path.
2. Initializes/pins the store identity if needed and derives the caller's public
   key pin from the local private key. Existing identity pins must still match.
3. Retains existing recipient pins and initializes missing pins from public-key
   registrations in the accepted Git checkout. Missing, invalid, or symlinked
   registration files fail migration without replacing the record.
4. Takes the record transaction lock and rechecks the current generation. If
   another reader has migrated it, verifies that signed record instead.
5. Otherwise verifies/decrypts the current legacy record privately, creates a
   fresh master key, and rewrites every recipient envelope as signed v2.
6. Publishes the complete record before allowing plaintext or key output.

This makes legacy stores migrate without separate recipient registration.
The accepted Git checkout supplies trust for the initial public-key registrations;
migration leaves uncommitted changes for review. A failed attempt may initialize
local pins, but leaves the original record intact. A signed store on
a new machine still requires explicit initialization and signer registration.

The initial legacy checkout must be trusted: its HMAC authenticates its value,
not its secret name or recipient list. Migration cannot retroactively prove
those historical associations. Missing or invalid tags require a trusted backup
or replacement from trusted plaintext. Already signed v2 records are verified
and left unchanged. `hash` and `verify` never recreate missing authentication
data on a signed record.
