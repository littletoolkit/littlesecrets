% LITTLESECRETS(1) Version 1.0.1 | LittleSecrets Documentation

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
- Secrets are encrypted with AES-256-CBC using random keys
- Each secret's encryption key is then encrypted with RSA (default 2048-bit, configurable to 4096-bit using each authorized user's public key)
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
: Set the private key used for decryption (default: $HOME/.ssh/id_rsa)

**-u**, **--user** *USER*
: Set user name (default: $USER)

**--host** *HOST*
: Set host name (default: $HOSTNAME)

**-s**, **--store** *PATH*
: Set store path (default: .littlesecrets)

**-f**, **--format** *FORMAT*
: Set output format to `text` or `json`. Global options must appear before the command.

**--binary**, **--text**
: In JSON mode, force binary values to base64 or force values to text. These options cannot be combined.

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
: Create `DIRECTORY/.littlesecrets` (default: current directory)

**list**, **ls** [*SECRET_EXPR*...]
: List matching secret names and recipients. With no expression, list all secrets.

**get** *SECRET*
: Retrieve the value of a secret

**add**, **set** *SECRET* [*VALUE*]
: Set a value. If `VALUE` is omitted, read it from stdin.

**remove** *SECRET*
: Remove a secret

**grant** *SECRET_EXPR* *USER_EXPR*...
: Grant matching users access to matching secrets. Quote expressions such as `*`.

**revoke** *SECRET_EXPR* *USER_EXPR*...
: Revoke matching users' access to matching secrets.

**register** [*USER[@HOST]*] [*PUBLIC_KEY*]
: Register a public key. If the user is omitted, use the configured user and host.

**deregister** *USER[@HOST]* [*PUBLIC_KEY*]
: De-register a user's public-key registration. With *USER@HOST*, removes the
matching host registration; with *USER*, removes matching registrations from all
of that user's hosts.

**users** [*USER_EXPR*...]
: List registered users and hosts matching the expressions.

**access** [*SECRET_EXPR*...]
: List recipients by secret in `SECRET: user@host ...` format.

**hash** [*SECRET_EXPR*...]
: Create or update HMACs for matching secrets. With no expression, process all secrets.

**verify** [*SECRET_EXPR*...]
: Verify HMACs without modifying secrets. Missing or invalid HMACs fail.

**export** [*VAR=SECRET...]
: Output shell assignments. With no arguments, export all secrets.

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
: Comma-separated list of options (default: hmac)

**LITTLESECRETS_OPENSSL_BIN**
: Path to the OpenSSL binary (default: openssl). This variable is validated at startup and made readonly to prevent tampering. The path must point to an executable file and cannot contain shell metacharacters. For security, use absolute paths when possible.

**LITTLESECRETS_LOG_FILTER**
: Optional space-separated log categories used by library callers. The default is `warning`; the CLI flags **--quiet**, **--verbose**, and **--debug** provide the supported user-facing levels.

# FILES

*.littlesecrets/*
: Default location of the secrets store

*.littlesecrets/secret/*
: Directory containing encrypted secrets, HMAC signatures, and encrypted keys

*.littlesecrets/user/*
: Directory containing user public keys, organized by user/host (e.g., alice/laptop.pubkey)

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

Report bugs at: https://github.com/yourusername/littlesecrets/issues

# COPYRIGHT

Copyright © 2025 LittleWorkshop LLC. License MIT.

# SEE ALSO

**ssh-keygen**(1), **openssl**(1)
