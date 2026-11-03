# Command Line Interface

The tool exposes the following CLI. `<NAME>` is required, `[NAME]` is optional,
`<NAME>...` means one or more arguments, and `[NAME...]` means zero or more.
`*_EXPR` arguments are quoted shell glob expressions.

- `init [DIRECTORY]` creates `DIRECTORY/.littlesecrets` and pins its identity locally.
- `list|ls [SECRET_EXPR...]` lists matching secret names and recipients.
- `get SECRET` automatically migrates a valid unsigned historical record, authenticates it, and writes its value byte-for-byte.
- `add|set SECRET [VALUE]` replaces a record, or reads its value from stdin when omitted; binary bytes and trailing newlines are preserved.
- `ensure SECRET` returns a value, creating it when missing.
- `remove SECRET` removes a secret.
- `has SECRET_EXPR...` returns 0 if any secret matches, otherwise 1, and writes nothing.
- `grant SECRET_EXPR USER_EXPR...` grants matching users access to matching secrets.
- `revoke SECRET_EXPR USER_EXPR...` removes matching recipient envelopes and rotates the master key for the remaining pinned recipients, including after deregistration.
- `access [SECRET_EXPR...]` lists recipients by secret.
- `register [USER[@HOST]] [PUBLIC_KEY]` registers and locally pins an independently verified public key. An explicit `USER@HOST` overrides key comments.
- `deregister USER[@HOST] [PUBLIC_KEY]` removes shared registrations; local pins and recipient envelopes are retained.
- `users [USER_EXPR...]` lists registered users and hosts.
- `hash [SECRET_EXPR...]` prints authenticated HMACs; no expression means all secrets. Unsigned records migrate first; signed records remain unchanged.
- `verify [SECRET_EXPR...]` verifies signatures and HMACs, migrating unsigned records first; inaccessible or invalid records fail.
- `upgrade [SECRET_EXPR...]` eagerly migrates matching records to signed v2, preserving recipients. Already signed v2 records are verified and skipped.
- `export [VAR=SECRET...]` outputs shell assignments or JSON; no arguments means all secrets. Failure emits no stdout. Shell export rejects NUL bytes.
- `find SECRET_EXPR` searches every ancestor store and prints `SECRET: STORE_PATH`.
- `info` shows the active store and other ancestor stores.
- `help [COMMAND]` shows general or command-specific help.
- `version` shows version information.

In the commands:

- `SECRET_EXPR` and `USER_EXPR` are glob-like patterns, matching `*` and `?`; callers should quote them.
- Any failure will return to an error message and a return code of `1`
- Global options must appear before `COMMAND`; `COMMAND --help` is equivalent to `help COMMAND`.
- `find` returns `1` when no match is found.
- `verify` is read-only for signed records and returns `1` for missing, inaccessible, or invalid authentication data.
- Missing authentication data is never recreated, and cannot be bypassed through `LITTLESECRETS_OPTIONS`.
- `get`, `ensure`, `hash`, `verify`, `export`, `grant`, and `revoke` migrate valid unsigned records automatically. After HMAC verification, missing recipient pins are initialized from registrations in the accepted Git checkout; the caller's pin is derived from its private key. Missing or invalid recipient keys fail migration without replacing the record.
- `set` uses fresh encryption and grants the writer's locally trusted registered hosts. Other recipients must be granted again.
- Wildcard operations are transactional per secret, not across the whole selection.

The tool supports the following global options. Missing values and invalid
formats are errors. `--binary` and `--text` require JSON output and cannot be
combined:

- `-k|--key` set the RSA private-key path for decryption and signing
- `-u|--user` set the user name (defaults to `$USER`)
- `--host` set the host name (defaults to `$HOSTNAME`)
- `-s|--store` set the path (or relative name) of the secrets store (defaults to `.littlesecrets`)
- `-fjson | --format=json | -f json` switch output to JSON (supported by: `list`, `users`, `access`, `add`, `set`, `get`, `ensure`, `export`, `info`)
- `--binary` (JSON mode) force base64 output for values (adds `"encoding":"base64"` even for textual secrets)
- `--text` (JSON mode) force UTF-8 text output; invalid UTF-8 fails
- `-q|--quiet` suppress warnings and routine diagnostics (errors are still reported)
- `--verbose` show routine operation details and progress on stderr
- `--debug` show diagnostic details and error stack traces on stderr
- `--v1` use the v1 symmetric scheme for `add`/`set` and newly created `ensure` values, with signed identity-bound records
- `--v2` use signed v2 records for those writes (the default)
- `--allow-legacy` compatibility option; automatic migration no longer needs it, and authentication remains mandatory

Output conventions:

- Command data is written to stdout only.
- Diagnostics, warnings, and progress output are written to stderr.
- The default level reports warnings, `--quiet` reports errors only, and `--verbose` reports routine action logs and progress.
- `--debug` additionally shows external command output and error stack traces.
- Colors are emitted only when stdout and stderr are terminals.

The tool uses the following environment variables:

- `LITTLESECRETS_USER` name of the user, defaults to `$USER`
- `LITTLESECRETS_HOST` name of the host, defaults to `$HOSTNAME`
- `LITTLESECRETS_KEY` path to the user's SSH private key, defaults to `$HOME/.ssh/id_rsa`
- `LITTLESECRETS_STORE` defaults to the name or path of the store, defaults to `.littlesecrets`
- `LITTLESECRETS_FORMAT_VERSION` format for new secrets, `v1` or `v2`, defaults to `v2`
- `LITTLESECRETS_KEYSIZE` historical setting, no longer used; master keys contain 32 random bytes
- `LITTLESECRETS_TRUST_DIR` private trust directory outside the shared store, defaults to `${XDG_STATE_HOME:-$HOME/.local/state}/littlesecrets`
- `LITTLESECRETS_ALLOW_LEGACY` compatibility setting for low-level decryption helpers; normal commands migrate automatically, while signed records always disable legacy fallbacks
- `LITTLESECRETS_OPENSSL_BIN` path to a trusted OpenSSL executable, defaults to `openssl`. Startup compatibility checks and a readonly variable do not authenticate the executable.
- `LITTLESECRETS_LOG_FILTER` optional space-separated log categories for library callers. The default category is `warning`.

Noting that:

- `LITTLESECRETS_KEY` / `--key` is a path to an unencrypted RSA private key, in SSH or OpenSSL format. Raw private-key contents are not accepted by this option.
- Explicit public-key arguments to `register` may be paths or public-key contents. Verify their identity independently before pinning them.
- New signed checkouts require `init` and local registration of signers/recipients. Legacy migration trusts registrations in the accepted Git checkout to initialize missing recipient pins after authenticating the old value. It leaves uncommitted changes for review.
