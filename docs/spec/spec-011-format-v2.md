# Format v2 Specification: Authenticated Encryption (Encrypt-then-MAC) & Format Migration

## 1. Overview & Motivation

LittleSecrets v1 uses AES-256-CBC alongside a detached HMAC signature (`secret.hmac`). In v1, the HMAC is computed over the **decrypted plaintext** after decryption has already taken place (MAC-then-Decrypt).

While functional, this approach has cryptographic and operational drawbacks:
1. **Decrypt-before-Verify Malleability**: Decrypting unauthenticated ciphertext exposes the CBC mode PKCS#7 padding to potential padding oracle attacks if error responses differ.
2. **Buffer Truncation**: Capturing plaintext into shell variables (`$(cat /dev/stdin)`) strips trailing newlines and truncates binary null bytes (`\x00`).
3. **OpenSSL CLI Constraints**: Standard OpenSSL CLI `enc` commands do not support GCM/AEAD ciphers (`enc: AEAD ciphers not supported`). Therefore, true Authenticated Encryption in portable shell scripts is achieved via the provably secure **Encrypt-then-MAC (EtM)** composition with AES-256-CBC and HMAC-SHA256.

Format v2 introduces:
- **Format Identification**: Automatic detection of v1 vs. v2 secrets.
- **Encrypt-then-MAC (EtM)**: Verifying the MAC over the ciphertext *before* attempting decryption.
- **Independent Key Derivation**: Splitting a master symmetric key into independent encryption ($K_{enc}$) and authentication ($K_{mac}$) keys.
- **Full Backward Compatibility**: Seamless, transparent reading of v1 legacy secrets alongside v2 secrets.
- **Upgrade Path**: A dedicated `upgrade` CLI command to migrate v1 secrets to v2 without user friction.

---

## 2. Format Identification & Detection

Each secret directory `.littlesecrets/secret/<name>/` stores:
- `secret.enc`: The symmetrically encrypted secret payload.
- `secret.hmac`: The cryptographic integrity signature.
- `<user>@<host>.key`: The recipient's RSA-OAEP encrypted symmetric master key.

### Format Distinctions

| Attribute | Format v1 (Legacy) | Format v2 (Modern) |
|---|---|---|
| **HMAC File Prefix** | None (64 hex characters) | `v2:etm:<64_hex_characters>` |
| **MAC Target** | Plaintext (`message = decrypted_secret`) | Ciphertext (`message = secret.enc`) |
| **Symmetric Cipher** | AES-256-CBC with PBKDF2 | AES-256-CBC with PBKDF2 ($K_{enc}$) |
| **Key Derivation** | Single key used for cipher & MAC | Dual independent keys via SHA-512 |
| **Verification Order** | Decrypt $\rightarrow$ Verify Plaintext MAC | Verify Ciphertext MAC $\rightarrow$ Decrypt |

### Detection Heuristic

Format detection is performed automatically by inspecting `secret.hmac`:
```bash
function ls_secret_format_version { # SECRET_NAME
    local hmac_path="$(ls_secret_hmac_path "$1")"
    if [ ! -e "$hmac_path" ]; then
        echo "v1"
        return 0
    fi
    local prefix
    prefix="$(head -c 7 "$hmac_path" 2>/dev/null || true)"
    if [ "$prefix" = "v2:etm:" ]; then
        echo "v2"
    else
        echo "v1"
    fi
}
```

---

## 3. Cryptographic Architecture (Format v2)

### 3.1 Key Generation and Derivation
1. **Master Symmetric Key ($K_{sym}$)**:
   A 32-byte (256-bit) cryptographically secure random key generated in hexadecimal format:
   $$K_{sym} = \text{openssl rand -hex 32}$$
   Encapsulated with `@LS:` base64 encoding for storage in recipient key envelopes.

2. **Dual Key Derivation**:
   Using SHA-512 to derive two non-overlapping 256-bit keys:
   $$K_{derived} = \text{SHA512}(K_{sym})$$
   - **Encryption Key ($K_{enc}$)**: First 32 bytes (64 hex characters)
     $$K_{enc} = K_{derived}[0..63]$$
   - **Authentication Key ($K_{mac}$)**: Second 32 bytes (64 hex characters)
     $$K_{mac} = K_{derived}[64..127]$$

### 3.2 Encryption & Integrity (Encrypt-then-MAC)
1. Plaintext $P$ is encrypted via AES-256-CBC:
   $$C = \text{AES-256-CBC-Encrypt}(K_{enc}, P)$$
   Output is written directly to `secret.enc`.
2. HMAC is computed directly over the ciphertext file `secret.enc`:
   $$T = \text{HMAC-SHA256}(K_{mac}, C)$$
3. The signature is written to `secret.hmac` with format prefix:
   $$\text{secret.hmac} = \text{"v2:etm:"} \parallel T$$

### 3.3 Decryption & Verification (Verify-then-Decrypt)
1. Recipient recovers $K_{sym}$ using their RSA private key with OAEP padding.
2. Derives $K_{mac}$ and $K_{enc}$ from $K_{sym}$.
3. Computes expected HMAC over `secret.enc` using $K_{mac}$.
4. Compares with stored signature in `secret.hmac` using constant-time comparison (`cmp -s`).
5. **Fail-Fast**: If the signature does not match, decryption aborts immediately. `secret.enc` is never parsed or passed to the AES decryptor.
6. Decrypts `secret.enc` using $K_{enc}$.

---

## 4. Backwards Compatibility & Dual Engine

### 4.1 Transparent Read Pipeline
`littlesecrets get <secret>` automatically branches:
- **v2 Secret Detected**:
  1. Derives $K_{mac}$ from decrypted symmetric key.
  2. Verifies `secret.hmac` against `secret.enc`.
  3. Decrypts `secret.enc` using $K_{enc}$.
- **v1 Secret Detected**:
  1. Decrypts `secret.enc` using legacy symmetric key.
  2. Verifies `secret.hmac` against decrypted plaintext.

### 4.2 Write Configuration
- Environment variable: `LITTLESECRETS_DEFAULT_FORMAT=v1|v2` (default: `v2`).
- CLI Flag: `littlesecrets add --v1 <secret>` or `littlesecrets add --v2 <secret>`.

### 4.3 Migration / Upgrade Command
A new CLI command `littlesecrets upgrade [SECRET_EXPR...]`:
1. Iterates over matching secrets.
2. If already v2, reports `Already up to date: <secret>`.
3. If v1:
   - Decrypts the secret using the v1 engine.
   - Generates a fresh 32-byte symmetric key.
   - Encrypts via v2 Encrypt-then-MAC.
   - Re-encrypts user recipient keys for all authorized users.
   - Updates `secret.enc` and `secret.hmac` atomically.
   - Reports `Upgraded: <secret> (v1 -> v2)`.

---

## 5. Security Invariants
1. Tampered ciphertexts in v2 secrets are rejected before any cryptographic unpadding occurs.
2. Legacy v1 secrets remain readable without requiring manual intervention.
3. Master symmetric keys in v2 are always 256 bits, eliminating key truncation risks.
4. All recipient keys continue to use RSA-OAEP with SHA-256 padding.
