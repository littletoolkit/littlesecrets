# CLI: Has Command

## Overview

The `has` command provides a way to test for the existence of secrets matching one or more glob patterns. It's designed for scripting and conditional logic where you need to check if secrets exist before performing operations.

## Command Specification

- `has EXPR…` checks if any secrets match any of the given `EXPR` patterns

## Behavior

### Input
- Accepts one or more glob-like patterns (`EXPR`)
- Patterns support `*` (wildcard for multiple characters) and `?` (wildcard for single character)
- If no arguments are provided, the command returns an error

### Output
- The command produces **no output** on stdout
- Returns exit code `0` if at least one secret matches any of the patterns
- Returns exit code `1` if no secrets match any of the patterns
- Returns exit code `1` and error message on stderr if called with no arguments

### Matching Logic
- Uses the same pattern matching logic as the `list` command
- Patterns are evaluated using shell globbing with `extglob` enabled
- Multiple patterns are combined with OR logic (matches any pattern)
- Pattern matching is case-sensitive

## Use Cases

### Scripting
```bash
# Check if database secrets exist before running migration
if littlesecrets has "db.*"; then
    echo "Database secrets found, running migration"
    run_migration
else
    echo "No database secrets found, skipping migration"
fi
```

### Conditional Operations
```bash
# Only run tests if test secrets are available
if littlesecrets has "test.*" "staging.*"; then
    run_integration_tests
fi
```

### Validation
```bash
# Ensure required secrets are present
required_secrets=("api.key" "db.password" "cache.token")
for pattern in "${required_secrets[@]}"; do
    if ! littlesecrets has "$pattern"; then
        echo "ERROR: Required secret pattern '$pattern' not found"
        exit 1
    fi
done
```

## Error Handling

### No Arguments
```
$ littlesecrets has
has: Missing secret pattern
```
Exit code: `1`

### Store Not Found
If no littlesecrets store is found in the current directory or ancestors:
```
$ littlesecrets has "test.*"
[ls] ! ERR LittleSecrets Command failed 1: !!
```
Exit code: `1`

## Integration with Other Commands

The `has` command complements existing commands:

- **list**: Shows what secrets exist, `has` tells you if specific patterns match
- **get**: Retrieves a specific secret, `has` validates it exists first
- **ensure**: Creates secrets if they don't exist, `has` checks existence without creating

## Implementation Notes

- Leverages existing `ls_secret_list` function for pattern matching
- Uses the same glob pattern syntax as other commands for consistency
- Designed to be silent (no stdout output) for clean scripting integration
- Exit codes follow Unix conventions: `0` for success/true, `1` for failure/false