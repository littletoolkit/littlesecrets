--
Id: SEC-16
Title: Hard Dependency on Non-Standard xxd Utility (MEDIUM)
Location: src/sh/littlesecrets.sh:973, 975, 991, 995, 1592, 1594
--

ls_hmac and ls_secret_hmac_key depend on `xxd` for hexadecimal conversion and hex-to-binary decoding.
- Impact:
`xxd` is not a standard POSIX tool and is missing in minimal Linux distributions, busybox environments, and lightweight container images. On systems without xxd, HMAC creation, verification, and secret addition fail.
- Remediation:
Replace `xxd` dependencies with standard tools such as `od`, `hexdump`, or OpenSSL's native formatting flags.
