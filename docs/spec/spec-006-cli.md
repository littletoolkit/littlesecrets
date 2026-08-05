# Command Line Interface

The tool should have the following CLI:

- `add|set SECRET [CONTENT]` sets the given secret to the given content.
- `get SECRET` returns the given secret.
- `list EXPR…` returns a list of secrets that match any of `EXPR`
- `access EXPR…` shows who can access the secrets that match any of `EXPR`
- `remove SECRET` removes the secret
- `grant SECRET EXPR…` grants the secrets to all users matching any of `EXPR`; a user expression of `*` grants access to every registered user and host
- `revoke SECRET EXPR…` revoke the secrets from all users matching any of `EXPR`
- `register USER KEY?` registers the given key for the given user
- `deregister USER KEY?` de-registers the given key (or all key) for the given user
- `ensure SECRET` ensures a secret exists (creates if missing)
- `has EXPR…` checks if any secrets match the given patterns (returns 0 if found, 1 if not found)
- `find NAMEISH` finds matching secrets in all littlesecrets repositories in the current path and its ancestors
- `info` shows repository information (path, users, secrets)

In the commands:

- `EXPR` is a glob-like pattern, matching `*` and `?`
- Any failure will return to an error message and a return code of `1`
- `find` reports each matching secret and its repository path, and returns `1` when no match is found

The tool support the following global options:

- `-k|--key` set the private key to use for decryption (path or key contents)
- `-u|--user` set the user name (defaults to `$USER`)
- `--host` set the host name (defaults to `$HOSTNAME`)
- `-s|--store` set the path (or relative name) of the secrets store (defaults to `.littlesecrets`)
- `-fjson | --format=json | -f json` switch output to JSON (supported by: `list`, `users`, `access`, `add`, `set`, `get`, `ensure`, `export`)
- `--binary` (JSON mode) force base64 output for values (adds `"encoding":"base64"` even for textual secrets)
- `--text` (JSON mode) force plain text output for values (suppresses `encoding` even for binary secrets)

The tool uses the following environment variables:

- `LITTLESECRETS_USER` name of the user, defaults to `$USER`
- `LITTLESECRETS_KEY` path to the user's SSH private key, defaults to `$HOME/.ssh/id_rsa`
- `LITTLESECRETS_STORE` defaults to the name or path of the store, defaults to `.littlesecrets`
- `LITTLESECRETS_OPENSSL_BIN` path to the OpenSSL binary, defaults to `openssl`. This is validated at startup (must be executable, cannot contain shell metacharacters) and made readonly to prevent tampering.

Noting that:

- The key (`LITTLESECRETS_KEY` or `--key`) can be either a path or the actual contents of the key,
  and can be either the public or private key, in either SSH or OpenSSL format. The CLI tool
  will automatically perform conversions and will fail if the key is not expected (ie. a private
  key is required when a public key is given).
- The `LITTLESECRETS_OPENSSL_BIN` variable is security-sensitive. It is validated to ensure it points to a real executable file and does not contain command injection attempts. The validation happens once at script startup and the variable is then made readonly.
