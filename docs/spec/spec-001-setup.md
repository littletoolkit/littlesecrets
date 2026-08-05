# Goal

The goal is to write a shared secrets manager that can work for a team to
safely store and share secrets in a git repository.

The current filesystem implementation stores data in `.littlesecrets`:

- Registered public keys are normalized to PEM and stored at
  `user/<user>/<host>.pubkey`.
- Each secret is stored at `secret/<name>/secret.enc`.
- Each recipient receives an encrypted copy of the secret key at
  `secret/<name>/<user>@<host>.key`.
- An optional integrity value is stored at `secret/<name>/secret.hmac`.

Granting access decrypts the caller's secret key and encrypts it for each
selected registered user and host.

