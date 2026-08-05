# Store

The Secret store is where secrets, public keys and encrypted keys are stored.
The current implementation provides a filesystem store. Archive, object-store,
and database backends are future work and are not part of the CLI contract.

The store uses cryptographic backends, which was defined earlier.

The store is expected to store data in hierarchical fashion, following this structure:

```
secret/                        # Stores the secrets
  <name>/
    secret.enc                 # Secret, encrypted with its key
    secret.hmac                # HMAC of secret and encryption key
    <user>@<host>.key          # Encrypted secret key for a user and host

user/                          # Stores the users
  <name>/                      # User Name
    <host>.pubkey              # Normalized User & Host PubKey
```

Note that it is important for the store to know when items were updated, as for
instance if a PubKey is updated, all corresponding EnKeys will be invalidated
and will need to be recreated.


The filesystem store supports the CLI operations defined in `spec-006-cli.md`:

- Adding or updating a secret encrypts its value and creates a recipient key for
  the current user when necessary.
- Granting creates recipient keys for matching registered users and hosts.
- Revoking removes matching recipient keys. It does not mark a secret for
  rotation; users must rotate a secret after revocation when required.
- Registering replaces the public key for one user and host. Existing recipient
  keys are not automatically regenerated.
- Deregistering removes one matching key, one host key, or all host keys for a
  user.

Groups and secret metadata are not implemented.
