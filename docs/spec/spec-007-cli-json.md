# JSON output format

The `-fjson` or `--format=json` option supports JSON outputs for the following commands:


## `list`

```
{
  "${secret.name}":["${user.name}@${user.host}", …]
}
```

## `add`, `set`, `get` and `ensure`

```
{
  "name":"${secret.name}",
  "value":"${secret.value}"
}
```

Binary values are base64 encoded and include an `encoding` field:

```
{
  "name":"${secret.name}",
  "value":"${secret.value}",
  "encoding":"base64"
}
```

You can override automatic binary detection:

- `--binary` forces base64 encoding (and the `encoding` field) for all values.
- `--text` forces plain text output (no `encoding` field) even if the value contains non-text bytes.

Automatic detection treats a value (or exported secret) as binary if the underlying decrypted file contains control characters (except tab, CR, LF) or high-bit bytes. Forced flags take precedence over detection.

## `export`

Export is a list of payloads like `get` and `ensure`
```
[{
  "name":"${secret.name}",
  "value":"${secret.value}",
  "encoding":"base64"
}]
```

## `users` and `access`

```
{
  "${user.name}":["${user.host}", …]
}
```

## `info`

```
{
  "path": "/absolute/path/to/.littlesecrets",
  "users": ["user1", "user2", "user3"],
  "secrets": ["secret1", "secret2", "secret3"]
}
```

