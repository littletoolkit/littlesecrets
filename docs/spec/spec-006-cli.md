# Command Line Interface

The tool exposes the following CLI. `<NAME>` is required, `[NAME]` is optional,
`<NAME>...` means one or more arguments, and `[NAME...]` means zero or more.
`*_EXPR` arguments are quoted shell glob expressions.

- `init [DIRECTORY]` creates `DIRECTORY/.littlesecrets`.
- `list|ls [SECRET_EXPR...]` lists matching secret names and recipients.
- `get SECRET` writes one secret value.
- `add|set SECRET [VALUE]` sets a value, or reads it from stdin when omitted.
- `ensure SECRET` returns a value, creating it when missing.
- `remove SECRET` removes a secret.
- `has SECRET_EXPR...` returns 0 if any secret matches, otherwise 1, and writes nothing.
- `grant SECRET_EXPR USER_EXPR...` grants matching users access to matching secrets.
- `revoke SECRET_EXPR USER_EXPR...` revokes matching users' access.
- `access [SECRET_EXPR...]` lists recipients by secret.
- `register [USER[@HOST]] [PUBLIC_KEY]` registers a public key.
- `deregister USER[@HOST] [PUBLIC_KEY]` removes registered public keys.
- `users [USER_EXPR...]` lists registered users and hosts.
- `hash [SECRET_EXPR...]` creates or updates HMACs; no expression means all secrets.
- `verify [SECRET_EXPR...]` verifies HMACs without modifying secrets; missing or invalid HMACs fail.
- `export [VAR=SECRET...]` outputs shell assignments; no arguments means all secrets.
- `find SECRET_EXPR` searches every ancestor store and prints `SECRET: STORE_PATH`.
- `info` shows the active store and other ancestor stores.
- `help [COMMAND]` shows general or command-specific help.
- `version` shows version information.

In the commands:

- `SECRET_EXPR` and `USER_EXPR` are glob-like patterns, matching `*` and `?`; callers should quote them.
- Any failure will return to an error message and a return code of `1`
- Global options must appear before `COMMAND`; `COMMAND --help` is equivalent to `help COMMAND`.
- `find` returns `1` when no match is found.
- `verify` is read-only and returns `1` for missing, inaccessible, or invalid HMACs.

The tool supports the following global options. Missing values and invalid
formats are errors. `--binary` and `--text` require JSON output and cannot be
combined:

- `-k|--key` set the private key to use for decryption (path or key contents)
- `-u|--user` set the user name (defaults to `$USER`)
- `--host` set the host name (defaults to `$HOSTNAME`)
- `-s|--store` set the path (or relative name) of the secrets store (defaults to `.littlesecrets`)
- `-fjson | --format=json | -f json` switch output to JSON (supported by: `list`, `users`, `access`, `add`, `set`, `get`, `ensure`, `export`)
- `--binary` (JSON mode) force base64 output for values (adds `"encoding":"base64"` even for textual secrets)
- `--text` (JSON mode) force plain text output for values (suppresses `encoding` even for binary secrets)
- `-q|--quiet` suppress warnings and routine diagnostics (errors are still reported)
- `--verbose` show routine operation details and progress on stderr
- `--debug` show diagnostic details and error stack traces on stderr

Output conventions:

- Command data is written to stdout only.
- Diagnostics, warnings, and progress output are written to stderr.
- The default level reports warnings, `--quiet` reports errors only, and `--verbose` reports routine action logs and progress.
- `--debug` additionally shows external command output and error stack traces.
- Colors are emitted only when stdout and stderr are terminals.

The tool uses the following environment variables:

- `LITTLESECRETS_USER` name of the user, defaults to `$USER`
- `LITTLESECRETS_KEY` path to the user's SSH private key, defaults to `$HOME/.ssh/id_rsa`
- `LITTLESECRETS_STORE` defaults to the name or path of the store, defaults to `.littlesecrets`
- `LITTLESECRETS_OPENSSL_BIN` path to the OpenSSL binary, defaults to `openssl`. This is validated at startup (must be executable, cannot contain shell metacharacters) and made readonly to prevent tampering.
- `LITTLESECRETS_LOG_FILTER` optional space-separated log categories for library callers. The default category is `warning`.

Noting that:

- The key (`LITTLESECRETS_KEY` or `--key`) can be either a path or the actual contents of the key,
  and can be either the public or private key, in either SSH or OpenSSL format. The CLI tool
  will automatically perform conversions and will fail if the key is not expected (ie. a private
  key is required when a public key is given).
- The `LITTLESECRETS_OPENSSL_BIN` variable is security-sensitive. It is validated to ensure it points to a real executable file and does not contain command injection attempts. The validation happens once at script startup and the variable is then made readonly.
