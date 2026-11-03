# Binary Input and Output

`add` and `set` read stdin byte-for-byte without a binary-input flag. Raw `get`
preserves NUL bytes, arbitrary binary data, and trailing newlines:

```sh
littlesecrets add certificate <certificate.bin
littlesecrets get certificate >restored.bin
cmp certificate.bin restored.bin
```

Plaintext stays in private files rather than Bash variables, so command
substitution cannot strip bytes inside the read/write path. If a caller captures
raw output using `$(...)`, Bash still strips trailing newlines and cannot hold
NUL bytes; redirect to a file when exact bytes matter.

JSON output detects binary values and emits base64 with `"encoding":"base64"`.
Text strings escape JSON control characters and preserve trailing newlines.
`--binary` forces base64. `--text` requires valid UTF-8 and fails otherwise;
without `iconv`, only ASCII can be validated as text. These flags control JSON
output, not input interpretation.

Shell export preserves text exactly using literal quoting, but rejects NUL
bytes because shell variables cannot contain them. Both shell and JSON exports
buffer the complete result and return a nonzero status with no stdout if any
record fails authentication, decryption, or encoding.
