# Info Command

The `info` command provides a quick overview of the LittleSecrets repository, showing key information about the store, registered users, and available secrets.

## Command

```
info
```

## Output Format

### Text Format (default)

The command outputs three lines with KEY: VALUE format:

```
Path: <absolute-path-to-repo>
Users: <user> <user> <user>
Secrets: <secret> <secret> <secret>
```

- **Path**: Absolute path to the `.littlesecrets` store directory
- **Users**: Space-separated list of unique usernames registered in the store
- **Secrets**: Space-separated list of secret names stored in the repository

If there are no users or secrets, the value will be `(none)`.

### JSON Format (`--format=json`)

When JSON format is requested, the output is a JSON object:

```json
{
  "path": "/absolute/path/to/.littlesecrets",
  "users": ["user1", "user2", "user3"],
  "secrets": ["secret1", "secret2", "secret3"]
}
```

## Behavior

1. **Store Discovery**: Uses the standard store discovery mechanism (searches up directory tree for `.littlesecrets` or uses `--store` option)
2. **Error Handling**: If no store is found, returns an error message and exit code 1
3. **User Listing**: Extracts unique usernames from registered user keys (removes host information)
4. **Secret Listing**: Lists all available secrets in the store

## Examples

### Basic Usage

```bash
$ littlesecrets info
Path: /home/user/project/.littlesecrets
Users: alice bob
Secrets: db.password api.key
```

### Empty Store

```bash
$ littlesecrets info
Path: /home/user/empty/.littlesecrets
Users: (none)
Secrets: (none)
```

### JSON Output

```bash
$ littlesecrets info --format=json
{
  "path": "/home/user/project/.littlesecrets",
  "users": ["alice", "bob"],
  "secrets": ["db.password", "api.key"]
}
```

### Custom Store

```bash
$ littlesecrets --store /path/to/custom-store info
Path: /path/to/custom-store
Users: alice
Secrets: secret1
```

## Return Codes

- **0**: Success
- **1**: No store found or other error

## Implementation Notes

- Uses `ls_store()` to locate the store
- Uses `realpath()` to get absolute path
- Uses `ls_user_list()` and extracts unique usernames with `cut -d: -f1 | sort -u`
- Uses `ls_secret_list()` to get all secrets
- Follows existing JSON formatting patterns used by other commands