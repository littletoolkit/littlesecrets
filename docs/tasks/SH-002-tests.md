# Test Cases

Looking at the available bash-based test suites like `tests/sh/cli-addget.sh`,
using the testing library `tests/sh/lib-testing.sh`. Can your write the
following tests:

- `tests/cli-register.sh` that registers the public key for the given user and
  hosts, and validates that he corresponding key file exists and is in the
  expected format. It should exercise the different combinations of `--user`,
  `--host` and `--key` parameters as well.
