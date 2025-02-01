% LITTLESECRETS(1) Version 1.0.0 | LittleSecrets Documentation

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

**Flexible Storage**
: Secrets can be safely stored on any backend: local filesystem, Git repository, file archive, SQLite database, or cloud services like AWS Secrets Manager.

**Strong Encryption**
: Uses industry-standard cryptography:
- Secrets are encrypted with AES-256-GCM using random keys
- Each secret's encryption key is then encrypted with RSA-4096 (using each authorized user's public key)
- Supports both OpenSSH and OpenSSL key formats
- No shared passwords or master keys required

The system is designed to be git-friendly, allowing teams to safely store encrypted secrets alongside their code while maintaining full audit history of access changes.

# OPTIONS

**-h**, **--help**
: Show help message and exit

**-v**, **--version**
: Show version information

**-k**, **--key** *KEY*
: Set private key path (default: $HOME/.ssh/id_rsa)

**-u**, **--user** *USER*
: Set user name (default: $USER)

**--host** *HOST*
: Set host name (default: $HOSTNAME)

**-s**, **--store** *PATH*
: Set store path (default: .littlesecrets)

# COMMANDS

**init** [*path*]
: Initialize a new secrets store at the specified path (default: current directory)

**list**, **ls** [*EXPR*...]
: List secrets matching the given glob expressions

**get** *SECRET*
: Retrieve the value of a secret

**add**, **set** *SECRET* [*CONTENT*]
: Set a secret's value. If content is not provided, reads from stdin

**remove** *SECRET*
: Remove a secret

**grant** *SECRET* *EXPR*...
: Grant access to users matching the glob expressions

**revoke** *SECRET* *EXPR*...
: Revoke access from users matching the glob expressions

**register** [*USER[@HOST]*] [*KEY*]
: Register a user's public key for a specific host. If HOST is not specified, uses LITTLESECRETS_HOST.

**deregister** *USER[@HOST]*] [*KEY*]
: De-register a user's public key from a specific host

**users** [*EXPR*...]
: List users matching the glob expressions

**access** [*EXPR*...]
: List users with access to secrets. If EXPR is provided, only show secrets matching the expressions. Format is "secret:user1@host1 user2@host2 ..."

# ENVIRONMENT

**LITTLESECRETS_USER**
: Name of the user (defaults to $USER)

**LITTLESECRETS_HOST**
: Name of the host (defaults to $HOSTNAME)

**LITTLESECRETS_KEY**
: Path to the user's SSH private key (defaults to $HOME/.ssh/id_rsa)

**LITTLESECRETS_STORE**
: Path to the secrets store (defaults to .littlesecrets)

# FILES

*.littlesecrets/*
: Default location of the secrets store

*.littlesecrets/secrets/*
: Directory containing encrypted secrets

*.littlesecrets/users/*
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

# EXIT STATUS

**0**
: Success

**1**
: Various errors (invalid arguments, encryption failure, etc.)

# BUGS

Report bugs at: https://github.com/yourusername/littlesecrets/issues

# COPYRIGHT

Copyright © 2025 LittleWorkshop LLC. License MIT.

# SEE ALSO

**ssh-keygen**(1), **openssl**(1)
