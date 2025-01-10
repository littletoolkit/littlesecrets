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

The cryptography should be implemented as backends matching.

For asymmetric crypto backends (AsmCrypto):

- `aenc(data, pubkey)` asymmetrically encrypts the given data with the given
  public key, making sure that `data` does not exceeds the size that can be
  encrypted by `pubkey`

- `adec(aencdata, privkey)` decrypts the asymmetrically encrypted data using
  the private key.

For symmetric crypto backends (SymCrypto):

- `enc(data, key)` symmetrically encrypts the data with the given key

- `dec(encdata, key)` symmetrically decrypts the data with the given key

Crypto backends should have a unique `name` that can be used to identify the
format.

