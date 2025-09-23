# Command Line Interface

The tool should have the following CLI:

- `add|set SECRET [CONTENT]` sets the given secret to the given content.
- `get SECRET` returns the given secret.
- `list EXPR…` returns a list of secrets that match any of `EXPR`
- `access EXPR…` shows who can access the secrets that match any of `EXPR`
- `remove SECRET` removes the secret
- `grant SECRET EXPR…` grants the secrets to all users matching any of `EXPR`
- `revoke SECRET EXPR…` revoke the secrets from all users matching any of `EXPR`
- `register USER KEY?` registers the given key for the given user
- `deregister USER KEY?` de-registers the given key (or all key) for the given user

In the commands:

- `EXPR` is a glob-like pattern, matching `*` and `?`
- Any failure will return to an error message and a return code of `1`

The tool support the following global options:

- `-k|--key` to set the private key to use for decryption
- `-u|--user` to set the user name
- `-s|--store` the path to the secrets store

The tool uses the following environment variables:

- `LITTLESECRETS_USER` name of the user, defaults to `$USER`
- `LITTLESECRETS_KEY` path to the user's SSH private key, defaults to `$HOME/.ssh/id_rsa`
- `LITTLESECRETS_STORE` defaults to the name or path of the store, defaults to `.littlesecrets`

Noting that:

- The key (`LITTLESECRETS_KEY` or `--key`) can be either a path or the actual contents of the key,
  and can be either the public or private key, in either SSH or OpenSSL format. The CLI tool
  will automatically perform conversions and will fail if the key is not expected (ie. a private
  key is required when a public key is given).

