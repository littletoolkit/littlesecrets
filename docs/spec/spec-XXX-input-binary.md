# Binary Data

`littlesecrets` should support binary data using the `--binary` flag.

- `cat FILE | littlesecrets add --binary SECRET`
- `littlesecrets get SECRET`

To do so:

- `add` should use `ls_encode` to process the input when `binary` is set.
- `add` without the `--binary` flag will strip NULL bytes, ideally we should warn of fail
   when a binary input is detected. However, we don't want to store the input on the
   file system as we don't want to leak the secret.
- `get` should detect if the value uses the `@LS:` encoding marker and process it with `ls_decode` if it does

Additionally:

- `littlesecrets {encode,decode}` should respectively allow to ls_encode/decode
  files.
