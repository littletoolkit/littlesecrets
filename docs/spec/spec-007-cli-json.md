# JSON output format

The `-fjson` or `--format=json` option supports JSON outputs for the following commands:


## `list`

```
{
  "${secret.name}":["${user.name}@${user.host}", …]
}
```

## `get` and `ensure`

```
{
  "name":"${secret.name}",
  "value":"${secret.value}"
}
```

Note that if the secret is binary it is base64 encoded


```
{
  "name":"${secret.name}",
  "value":"${secret.value}",
  "encoding":"base64"
}
```

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

