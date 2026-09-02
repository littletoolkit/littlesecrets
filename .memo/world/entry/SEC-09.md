--
Id: SEC-09
Title: Plaintext Secret Exposure via CLI Command Arguments (HIGH)
Location: src/sh/littlesecrets.sh:2380–2413
--

The CLI command `littlesecrets add <secret> [value]` allows passing the secret value as a command-line argument.
- Impact:
Process arguments are visible to any unprivileged user on the same system via /proc/<pid>/cmdline or commands like `ps aux`, exposing plaintext secrets in process listings.
- Remediation:
Discourage or deprecate passing secret values via command-line arguments. Prefer reading secrets from standard input (stdin) or interactive prompts.
