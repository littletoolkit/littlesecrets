# Info Command

The `info` command provides a quick overview of the LittleSecrets repository, showing key information about the store, registered users, and available secrets.

## Command

```
info
```

## Output Format

### Text Format (default)

The command outputs four lines with KEY: VALUE format:

```
Path: <absolute-path-to-repo>
Users: <user> <user> <user>
Secrets: <secret> <secret> <secret>
Repositories: <absolute-path-to-other-repo> <absolute-path-to-other-repo>
```

- **Path**: Absolute path to the `.littlesecrets` store directory
- **Users**: Space-separated list of unique usernames registered in the store
- **Secrets**: Space-separated list of secret names stored in the repository
- **Repositories**: Space-separated list of other `.littlesecrets` stores found in ancestor directories

If there are no users or secrets, the value will be `(none)`.

### JSON Format (`--format=json`)

When JSON format is requested, the output is a JSON object:

```json
{
  "path": "/absolute/path/to/.littlesecrets",
  "users": ["user1", "user2", "user3"],
  "secrets": ["secret1", "secret2", "secret3"],
  "repositories": ["/absolute/path/to/other/.littlesecrets"]
}
```

## Behavior

1. **Store Discovery**: Uses the standard store discovery mechanism (searches up directory tree for `.littlesecrets` or uses `--store` option)
2. **Error Handling**: If no store is found, returns an error message and exit code 1
3. **User Listing**: Extracts unique usernames from registered user keys (removes host information)
4. **Secret Listing**: Lists all available secrets in the store
5. **Repository Listing**: Lists other stores found while walking from the current directory to the filesystem root

## Examples

### Basic Usage

```bash
$ littlesecrets info
Path: /home/user/project/.littlesecrets
Users: alice bob
Secrets: db.password api.key
Repositories: /home/user/.littlesecrets
```

### Empty Store

```bash
$ littlesecrets info
Path: /home/user/empty/.littlesecrets
Users: (none)
Secrets: (none)
Repositories: (none)
```

### JSON Output

```bash
$ littlesecrets info --format=json
{
  "path": "/home/user/project/.littlesecrets",
  "users": ["alice", "bob"],
  "secrets": ["db.password", "api.key"],
  "repositories": []
}
```

### Custom Store

```bash
$ littlesecrets --store /path/to/custom-store info
Path: /path/to/custom-store
Users: alice
Secrets: secret1
Repositories: (none)
```

## Return Codes

- **0**: Success
- **1**: No store found or other error

## Implementation Notes

- Uses `ls_store()` to locate the current store and `ls_store_list()` to locate ancestor stores
- Uses `realpath()` to get absolute path
- Uses `ls_user_list()` and extracts unique usernames with `cut -d: -f1 | sort -u`
- Uses `ls_secret_list()` to get all secrets
- Follows existing JSON formatting patterns used by other commands
- The current store is excluded from `repositories`
