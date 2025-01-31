```
 _ _ _   _   _      __                    _
| (_) |_| |_| | ___/ _\ ___  ___ _ __ ___| |_ ___
| | | __| __| |/ _ \ \ / _ \/ __| '__/ _ \ __/ __|
| | | |_| |_| |  __/\ \  __/ (__| | |  __/ |_\__ \
|_|_|\__|\__|_|\___\__/\___|\___|_|  \___|\__|___/
```

*LittleSecrets* is secret sharing tool that can be used for
distributing secrets across machines and users, while safely storing the
secrets in local filesystems, Git repostories, archives or any unencrypted
strorage.

LittleSecrets' design is based on the *Secure and convenient secret management
in distributed computer systems* paper by Blazej Adamczyk, and relies primarily
on RSA keypairs and AES-256-CBC with PBKDF2 for encryption.

## Use Cases

- Managing secrets in your personal homelab, for instance having `dotsecrets`
  repository where you centralise your secrets and grant access to specific
  machines and users.

- Sharing secrets in a team, by either storing secrets in a shared repository,
  or storing secrets directly in your codebase repository, registering human user
  and machine users, granting and revoking access.

In a nutshell, the process is like so:

```bash
# Create a repository
littlesecrets init

# Add a secret
echo -n "SECRET!" | littlesecret add my.little.secret

# Retrieve the secret
littlesecret get my.little.secret

# Register someone's RSA public key
littlesecret register alice alice.rsa.pubkey

# Alternatively, if you share the repository the other user can simply
# do a `littlesecrets register` so that their key is registered.

# Grant access to the secret
littlesecret grant my.little.secret alice
```

## Features

- *Zero-Knowledge*: secret stores have no access to the plain text secrets or
  encryption keys.

- *Asymmetric Key Distribution*: RSA keys (SSH and OpenSSL) are used to represent
  users (humans or machines), and ensure only authorized users have access to
  specific secrets.

- *Support for multiple keys per user*: works for human user working across multiple
  machines.

- *Revocation mechanisms*: secrets can be revoked and rotated.

- *Strong Encryption*: symmetric encryption is AES-256-CBC with PBKDF2

- *Stateless Design*: no service or authentication is required, we rely on the
   cryptographic properties of keys.

Some caveats of the cryptographic model:

- We assume 2048bit for RSA keys, although this can be parameterised.

- We do not provide integrity verification of encrypted secrets, an attacker
  could replace an existing secret, however this can be mitigated when
  using a repository like Git to store secrets.

- Once a secret is granted to a user, the secret should be considered known.
  As a result, when you revoke access to a secret, you should also rotate it.

- Due to its stateless design, there is no audit log. Instead, we recommend
  to store the secrets in a Git repository for auditing.

## References

Papers & Articles:

- [Secure and convenient secret management in distributed computer](https://www.wseas.org/multimedia/journals/computers/2016/a565805-087.pdf), Blazej Adamczyk, WSEAS transactions on computers

- [Please Stop Encrypting with RSA Directly](https://soatok.blog/2021/01/20/please-stop-encrypting-with-rsa-directly/), which gives more details on what not to do when using RSA. We are using the recommended approach here.

- [How we share secrets at a fully remote startup](https://mill.plainopen.com/how-we-share-secrets-at-a-fully-remote-startup) presents a similar approach, and has interesting comments from the community, see Lobsters's stories [1](https://lobste.rs/s/wfmynv/how_we_share_secrets_at_fully_remote) and [2](https://lobste.rs/s/wfmynv/how_we_share_secrets_at_fully_remote). Our view is that

Related tools, compared to LittleSecrets:

- `sops`: Secrets OPerationS is more like a toolbox that can be used to build
   workflows similar to LittleSecrets, however there is more configuration and
   complexity involved.

- `age`: age is a lower-level encryption tool, which could be used as building
  block to achieve similar results.

Overall, `littlesecrets` is designed around a simple workflow and simple,
well-known, auditable primitives. If the workflows supported by `littlesecrets`
work for you, then its simplicity and ease of use should make it attractive.

