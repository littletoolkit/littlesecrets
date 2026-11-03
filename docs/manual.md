% LITTLESECRETS(1) Version 1.1.0 | LittleSecrets Documentation

# NAME

littlesecrets - A shared secrets manager for individual and teams

# SYNOPSIS

**littlesecrets** [*OPTIONS*] *COMMAND* [*ARGS*...]

# DESCRIPTION

LittleSecrets is a secure secrets management tool designed for individual and teams to safely store and share secrets. It provides:

**Multi-Machine Password Store**
: Works as a password manager across multiple machines, with per-device secret access control using device-specific SSH keys.

**Team Secret Sharing**
: Enables secure secret sharing amongst team members using their existing SSH keypairs - no need for new authentication systems.

**Local Storage**
: Secrets are stored in a local directory structure, making it git-friendly for version control and audit trails.

**Strong Encryption**
: Uses industry-standard cryptography:
- Secrets use AES-256-CBC with PBKDF2 and a fresh 32-byte random master key
- New secrets use Encrypt-then-MAC with HMAC-SHA256 over the ciphertext (format v2)
- Signed records bind the store identity, secret name, ciphertext, format, HMAC, and recipient envelopes
- Public keys and the store identity are pinned locally, outside the shared store
- Authentication is mandatory; missing or invalid authentication data causes failure
- Valid unsigned historical records migrate automatically on authenticated access
- Each secret's master key is wrapped with RSA-OAEP-SHA256 for each recipient
- Supports both OpenSSH and OpenSSL key formats
- No shared passwords or master keys required

The system is designed to be git-friendly, allowing teams to safely store encrypted secrets alongside their code while maintaining full audit history of access changes.

# OPTIONS

**-h**, **--help**
: Show help message and exit

**-v**, **--version**
: Show version information

**-q**, **--quiet**
: Suppress warnings and routine diagnostics. Errors are still reported.

**--verbose**
: Show routine operation details and progress on stderr.

**--debug**
: Show diagnostic details and error stack traces on stderr.

**-k**, **--key** *KEY*
: Set the RSA private-key path used for decryption and signing (default: $HOME/.ssh/id_rsa). Passphrase-protected keys are not supported.

**-u**, **--user** *USER*
: Set user name (default: $USER)

**--host** *HOST*
: Set host name (default: $HOSTNAME)

**-s**, **--store** *PATH*
: Set store path (default: .littlesecrets)

**-f**, **--format** *FORMAT*
: Set output format to `text` or `json`. Global options must appear before the command.

**--binary**, **--text**
: In JSON mode, force base64 or UTF-8 text output. `--text` rejects invalid UTF-8. These options cannot be combined.

**--v1**, **--v2**
: Select the format for `add`, `set`, and newly created `ensure` values; v2 is the default. Both formats produce signed, identity-bound records. Revocation and upgrade write v2.

**--allow-legacy**
: Compatibility option; normal commands already migrate valid legacy records automatically. It does not bypass HMAC verification or allow damaged signed records to be treated as legacy.

Commands write data only to stdout. Diagnostics, warnings, and progress output
are written to stderr. Routine operation details are hidden by default and can
be enabled with **--verbose** or **--debug**. ANSI colors are enabled only when
both output streams are terminals; set **NOCOLOR** to disable them explicitly.
The default level reports warnings, **--quiet** reports errors only, and
**--debug** additionally shows external command output and error stack traces.

# ARGUMENT CONVENTIONS

`<NAME>` is required, `[NAME]` is optional, `<NAME>...` means one or more,
and `[NAME...]` means zero or more. Names ending in `_EXPR` are shell glob
expressions and should be quoted. Commands use the nearest `.littlesecrets`
store unless otherwise stated. Use `find` to search all ancestor stores.

# COMMANDS

**init** [*DIRECTORY*]
: Create `DIRECTORY/.littlesecrets` (default: current directory) and pin its identity locally. Run this on a trusted checkout; an existing local identity pin is never replaced.

**list**, **ls** [*SECRET_EXPR*...]
: List matching secret names and recipients. With no expression, list all secrets.

**get** *SECRET*
: Authenticate and retrieve a secret, automatically migrating an unsigned historical record first. Raw output preserves every byte, including NUL bytes and trailing newlines. Failed migration returns no plaintext.

**add**, **set** *SECRET* [*VALUE*]
: Set a value with a fresh key. If `VALUE` is omitted, read all bytes from stdin. This replaces the record and grants the writer's locally trusted registered hosts; grant other recipients again after setting a value. Prefer stdin to keep values out of process arguments and shell history.

**remove** *SECRET*
: Remove a secret

**grant** *SECRET_EXPR* *USER_EXPR*...
: Authenticate each record, wrap its key for locally pinned recipients, and sign the updated record. Quote expressions such as `*`. Unsigned historical records migrate first.

**revoke** *SECRET_EXPR* *USER_EXPR*...
: Remove matching recipient envelopes and rotate the master key, re-encrypting for all remaining pinned recipients. This works after deregistration. Revoking the last recipient fails; use `remove` instead. Previously learned secret values and historical copies remain known to former recipients.

**register** [*USER[@HOST]*] [*PUBLIC_KEY*]
: Register and locally pin an independently verified public key. If omitted, derive the public key from the local private key. An explicit `USER@HOST` overrides SSH key comments. Registration can replace an existing pin; verify replacement keys independently.

**deregister** *USER[@HOST]* [*PUBLIC_KEY*]
: De-register a user's public-key registration. With *USER@HOST*, removes the
matching host registration; with *USER*, removes matching registrations from all
of that user's hosts.
Local pins and existing recipient envelopes are retained. Use `revoke` to remove
access to current records.

**users** [*USER_EXPR*...]
: List registered users and hosts matching the expressions.

**access** [*SECRET_EXPR*...]
: List recipients by secret in `SECRET: user@host ...` format.

**hash** [*SECRET_EXPR*...]
: Print authenticated HMACs for matching secrets, automatically migrating unsigned historical records first. Signed records are not modified. With no expression, process all secrets.

**verify** [*SECRET_EXPR*...]
: Verify signatures and HMACs, automatically migrating unsigned historical records first. Signed records are not modified. Missing tags, untrusted signers, inaccessible keys, and invalid records fail.

**upgrade** [*SECRET_EXPR*...]
: Eagerly migrate matching records to signed v2, rotating the master key and preserving recipients. Legacy migration initializes missing recipient pins from registrations in the trusted checkout; the caller's key is derived from the private key. Already signed v2 records are verified and left unchanged.

**export** [*VAR=SECRET*...]
: Output shell assignments, or JSON with `--format=json`. With no arguments, export all secrets. Any failure produces a nonzero status and no output. Shell export preserves trailing newlines and rejects NUL bytes; JSON represents binary values as base64 with an `encoding` field.

**ensure** *SECRET*
: Ensure a secret exists (create if missing). If the secret exists, returns its value. If not, creates a new random secret and returns it.

**has** *SECRET_EXPR*...
: Write nothing; return 0 if any secret matches, otherwise return 1.

**find** *SECRET_EXPR*
: Find matching secrets in every ancestor store and print `SECRET: STORE_PATH`.

**info**
: Show the active store, its users and secrets, and other ancestor stores.

**help** [*COMMAND*]
: Show general help or help for one command. `COMMAND --help` is equivalent.

# ENVIRONMENT

**LITTLESECRETS_USER**
: Name of the user (defaults to $USER)

**LITTLESECRETS_HOST**
: Name of the host (defaults to $HOSTNAME)

**LITTLESECRETS_KEY**
: Path to the user's SSH private key (defaults to $HOME/.ssh/id_rsa)

**LITTLESECRETS_STORE**
: Path to the secrets store (defaults to .littlesecrets)

**LITTLESECRETS_OPTIONS**
: Historical options variable. Removing `hmac` no longer disables authentication.

**LITTLESECRETS_FORMAT_VERSION**
: Format used for newly written secrets: `v1` or `v2` (default: `v2`)

**LITTLESECRETS_KEYSIZE**
: Historical variable, no longer used. Master keys contain 32 random bytes, independent of RSA key size. Generated RSA keys are 4096-bit.

**LITTLESECRETS_TRUST_DIR**
: Private local trust directory (default: `${XDG_STATE_HOME:-$HOME/.local/state}/littlesecrets`). Keep it outside the shared store and version control. Pins are indexed by the absolute store path.

**LITTLESECRETS_ALLOW_LEGACY**
: Compatibility setting for low-level decryption helpers. Normal commands migrate legacy records automatically regardless of this setting. Signed records always disable legacy fallbacks.

**LITTLESECRETS_OPENSSL_BIN**
: Path to the OpenSSL binary (default: openssl). Startup checks executability and the version string, then makes the variable readonly. These are compatibility checks, not authentication of the executable. Use a trusted local executable and `PATH`.

**LITTLESECRETS_LOG_FILTER**
: Optional space-separated log categories used by library callers. The default is `warning`; the CLI flags **--quiet**, **--verbose**, and **--debug** provide the supported user-facing levels.

# FILES

*.littlesecrets/*
: Default location of the secrets store

*.littlesecrets/secret/*
: Directory containing encrypted secrets, HMAC tags, signed format metadata, and encrypted recipient envelopes

*.littlesecrets/store.id*
: Random store identity, checked against the local pin

*.littlesecrets/user/*
: Directory containing user public keys, organized by user/host (e.g., alice/laptop.pubkey)

*$LITTLESECRETS_TRUST_DIR/*
: Checkout-specific store identity and public-key pins. Each checkout needs its own pins, including the signers of records it reads.

# TRUST AND MIGRATION

On a new or cloned signed checkout, run `init` to pin a trusted store identity, then
`register USER@HOST PUBLIC_KEY` for independently verified signers and recipients.
For signed records, copying public keys into the shared `user/` directory does
not establish trust. Legacy migration bootstraps missing pins as described below.
Moving a checkout to another absolute path requires establishing its local pins again.

Historical unsigned v1/v2 records migrate automatically when accessed by `get`,
`ensure`, `hash`, `verify`, `export`, `grant`, or `revoke`. After verifying the
existing HMAC, migration initializes the store identity if needed and derives
the caller's local public-key pin from the private key. A single-recipient
legacy store needs no setup or migration flags:

```sh
littlesecrets get db.password
```

For shared legacy records, migration trusts the accepted Git checkout and
automatically initializes missing recipient pins from
`user/<user>/<host>.pubkey`. Separate local registration is unnecessary.
Existing pins are retained. Missing, invalid, or symlinked registration files
stop migration with the original record intact; recipients are never dropped.
Migration leaves ordinary uncommitted file changes for Git review and does not
create a commit automatically.

`littlesecrets upgrade '*'` performs migration eagerly; `--allow-legacy` remains
accepted for older scripts but is no longer necessary. Signed stores cloned
onto a new machine still require explicit `init` and signer registration.

Use a trusted historical checkout: its HMAC authenticates the value but cannot
prove the original secret name or recipient list. Migration verifies that HMAC,
then rotates the key and signs the complete record in a locked transaction
before returning plaintext. v1 must decrypt privately to check its plaintext
HMAC. Missing or invalid tags, damaged signed metadata, and failed commits are
never repaired by accepting the current bytes. Recover a trusted backup or
supply trusted plaintext with `set`. Older clients cannot read the new
identity-bound envelopes and must not write to migrated stores.

# FILESYSTEM AND RECOVERY

Secret operations use per-secret locks. Writers stage a complete record and
retain the previous generation until publication; ordinary failures restore it
when possible. Readers authenticate and decrypt a private snapshot. Symlinks and
special filesystem entries in store/trust paths are rejected.

Temporary plaintext and key files live in a process-owned private directory
under `TMPDIR`, with restrictive permissions and cleanup on normal exit,
SIGINT, and SIGTERM. SIGKILL and power loss can leave temporary files, lock
directories, or `.ls-stage.*` / `.ls-backup.*` directories behind. After checking
that no holder is running, recover any retained record and explicitly remove
abandoned locks. Locks are never reclaimed automatically.

The local account, trust database, executables, and working filesystem must be
trusted. Signatures do not prevent replay of a previously valid record; use
trusted version history to establish freshness. Revocation rotates encryption
keys, not the external password/token stored as the value; rotate that credential
at its source if a former recipient must no longer use it.

# EXAMPLES

Initialize a new store:
```
littlesecrets init
```

Register a user:
```
littlesecrets register alice ~/.ssh/id_rsa.pub
```

Add a secret:
```
echo "mysecret123" | littlesecrets add db.password
```

Grant access to a team:
```
littlesecrets grant db.password "dev-*"
```

Register a user for multiple machines:
```
littlesecrets register alice@laptop
littlesecrets register alice@desktop
```

List who has access to secrets:
```
littlesecrets access              # all secrets
littlesecrets access "db.*"       # only db-related secrets
```

Grant access to specific machines:
```
littlesecrets grant api.key bob@laptop     # only bob's laptop
littlesecrets grant api.key bob            # all of bob's machines
```

Verify secret integrity:
```
littlesecrets verify db.password          # verify specific secret
littlesecrets verify                      # verify all secrets
```

Export secrets as environment variables:
```
littlesecrets export DB_PASS=db.password API_KEY=api.key
# Outputs: export DB_PASS='secretvalue'; export API_KEY='keyvalue'
```

Ensure a secret exists (creates if missing):
```
littlesecrets ensure api.key
# If exists: outputs the existing secret value
# If not exists: creates and outputs new random secret like "a7B9xK3mP2nQ8rL"
```

Check if secrets exist before running operations:
```
if littlesecrets has "db.*"; then
    echo "Database secrets found, running migration"
    run_migration
else
    echo "No database secrets found"
fi

# Check multiple patterns
if littlesecrets has "test.*" "staging.*"; then
    run_integration_tests
fi
```

Show repository information:
```
littlesecrets info
# Outputs:
# Path: /absolute/path/to/.littlesecrets
# Users: alice bob
# Secrets: db.password api.key
```

# EXIT STATUS

**0**
: Success. For the `has` command, this means at least one secret matched the given patterns.

**1**
: Various errors (invalid arguments, encryption failure, etc.). For the `has` command, this means no secrets matched the given patterns.

# BUGS

Report bugs at: https://github.com/littletoolkit/littlesecrets/issues

# COPYRIGHT

Copyright (c) 2025 LittleWorkshop Ltd. License BSD 3-Clause.

# SEE ALSO

**ssh-keygen**(1), **openssl**(1)
