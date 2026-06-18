```
  _ _ _   _   _      __                    _
 | (_) |_| |_| | ___/ _\ ___  ___ _ __ ___| |_ ___
 | | | __| __| |/ _ \ \ / _ \/ __| '__/ _ \ __/ __|
 | | | |_| |_| |  __/\ \  __/ (__| | |  __/ |_\__ \
 |_|_|\__|\__|_|\___\__/\___|\___|_|  \___|\__|___/
 ```

[![CI](https://github.com/littletoolkit/littlesecrets/actions/workflows/test.yml/badge.svg)](https://github.com/littletoolkit/littlesecrets/actions/workflows/test.yml)

*LittleSecrets* is secret sharing tool that can be used for
distributing secrets across machines and users, while safely storing the
secrets in local filesystems, Git repostories, archives or any unencrypted
strorage.

LittleSecrets' design is based on the *Secure and convenient secret management
in distributed computer systems* paper by Blazej Adamczyk, and relies primarily
on RSA keypairs and AES-256-CBC with PBKDF2 for encryption.

## Quick Start

Global options (excerpt): `-k|--key`, `-u|--user`, `--host`, `-s|--store`, `-fjson|--format=json|-f json`, `--binary`, `--text`.

- `--binary` forces base64 encoding of secret values in JSON output (adds `encoding` field)
- `--text` forces plain text emission of secret values in JSON output (suppresses `encoding` field)


You can install like so, you'll need Bash, OpenSSL, Coreutils and a POSIX
system.

```
curl -o littlesecrets https://raw.githubusercontent.com/littletoolkit/littlesecrets/refs/heads/main/src/sh/littlesecrets.sh
chmod +x littlesecrets
mv littlesecrets ~/.local/bin
```

and then

```bash
# Create a repository
littlesecrets init

# Add a secret
echo -n "SECRET!" | littlesecret add my.little.secret

# Retrieve the secret
littlesecrets get my.little.secret

# Register someone's RSA public key
littlesecrets register alice alice.rsa.pubkey

# Alternatively, if you share the repository the other user can simply
# do a `littlesecrets register` so that their key is registered.

# Grant access to the secret
littlesecrets grant my.little.secret alice
```

## Use Cases

- Managing secrets in your personal homelab, for instance having a `dotsecrets`
  repository where you centralise your secrets and grant access to specific
  machines and users. You can clone it to `~/.littlesecrets/` and sync it
  across devices.

- Sharing secrets in a team, by either storing secrets in a shared repository,
  or storing secrets directly in your codebase repository, registering human user
  and machine users, granting and revoking access.

`littlesecrets` is primarily intended to be used as a devops CLI tool, however
the store can easily be accessed and decrypted using common programming
languages thanks to relying on standard primitives.

Overall, `littlesecrets` is designed around a simple workflow and simple,
well-known, auditable primitives. If the workflows supported by `littlesecrets`
work for you, then its simplicity and ease of use should make it attractive.

## Features

- *Zero-Knowledge*: secret stores have no access to the plain text secrets or
  encryption keys.

- *Asymmetric Key Distribution*: RSA keys (SSH and OpenSSL) are used to represent
  users (humans or machines), and ensure only authorized users have access to
  specific secrets.

- *Support for multiple keys per user*: works for human user working across multiple
  machines.

- *Revocation mechanisms*: secrets can be revoked and rotated.

- *Strong Encryption*: symmetric encryption is AES-256-CBC with PBKDF2,
  authentication using HMAC.

- *Stateless Design*: no service or authentication is required, we rely on the
   cryptographic properties of keys.

Some caveats of the cryptographic model:

- The private keys corresponding to the registered SSH keys is what protect
  the secrets. If a key is compromised, all the secrets that have been granted
  are potentially compromised.

- We assume 2048bit for RSA keys, although this can be parameterised.

- We use AES-256-CBC (encryption) and HMAC (authentication). AES-256-GCM would
  be better, but is not available for good reasons
  (see `openssl aes-256-gcm` returning `aes-256-gcm: AEAD ciphers not supported`,
  also see [this openssl issue](https://github.com/openssl/openssl/issues/12220)
  and the [corresponding discussion](https://github.com/openssl/openssl/discussions/22269) for more detail).

- Once a secret is granted to a user, the secret should be considered known.
  As a result, when you revoke access to a secret, you should also rotate it.

- Due to its stateless design, there is no audit log. Instead, we recommend
  to store the secrets in a Git repository for auditing.

And some more general caveats for security:

- The CLI tool uses the shell and temporary files (cleanup, with appropriate
  permissions), which offers a window for a local attack.

- The CLI tool does not do strong input validation, it's meant to be run by
  yourself directly.

## References

Papers & Articles:

- [Secure and convenient secret management in distributed computer](https://www.wseas.org/multimedia/journals/computers/2016/a565805-087.pdf), Blazej Adamczyk, WSEAS transactions on computers

- [Please Stop Encrypting with RSA Directly](https://soatok.blog/2021/01/20/please-stop-encrypting-with-rsa-directly/), and its [follow-up](https://soatok.blog/2025/01/31/hell-is-overconfident-developers-writing-encryption-code/) which gives more details on what not to do when using RSA, while also advocating for leaving cryptography to cryptographers. Our view here is that the cryptographic approach we're using is simple and therefore can audited.

- [How we share secrets at a fully remote startup](https://mill.plainopen.com/how-we-share-secrets-at-a-fully-remote-startup) presents a similar approach, and has interesting comments from the community, see Lobsters's stories [1](https://lobste.rs/s/wfmynv/how_we_share_secrets_at_fully_remote) and [2](https://lobste.rs/s/wfmynv/how_we_share_secrets_at_fully_remote). Our view is that simplicity is a good feature to have for cryptography, as long as it relies on well-known primitives that are used properly, and that the caveats are clear.

Related tools, compared to LittleSecrets:

- [sops](https://github.com/getsops/sops): Secrets OPerationS is more like a toolbox that can be used to build
   workflows similar to LittleSecrets, however there is more configuration and
   complexity involved.

- [age](https://github.com/FiloSottile/age): age is a lower-level encryption tool, which we could use in lieu of the RSA/AES combo, however, this would require encrypting the secret for each user, therefore taking more space and requiring proof of the secret's original value, while also limiting the ability to decrypt to platform that have age implemented.

- [dotenvx](https://dotenvx.com/docs/quickstart/encryption): allows to encrypt your `.env` file, which is convenience but lacks the granularity of `littlesecrets`, where you encrypt (and grant) each secret independently.

