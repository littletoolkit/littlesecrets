# Goal

The goal is to write a shared secrets manager that can work for a team to
safely store and share secrets in a git repository.

The software works like so:

- secrets are shared in `.sharedsecrets` users register their ssh public key
- (any format accepted) in `.sharedsecrets/users/${USER}.pubkey` (the key would
- likely be normalised) a secret is encrypted in
- `.sharedsecret/secrets/${SECRET}`, where `secret.enc` is the encrypted secret
- and `${USER}.key.enc` is the key used to encrypt the secret, which can be
- decrypted using `$USER`'s private key. a user can grant access to a secret to
- another user, in which case the user will decrypt the secret's
- `$USER.key.enc` and encrypt it using
- `.sharedsecrets/users/$OTHERUSER.pubkey`, saving the result in the secret's
- directory as `$OTHERUSER.key.env`


