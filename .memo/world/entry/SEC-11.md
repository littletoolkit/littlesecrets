--
Id: SEC-11
Title: HMAC Verification Bypassed in Core get and ensure Commands (MEDIUM)
Location: src/sh/littlesecrets.sh:1709–1747, 1661–1707
--

Function ls_secret_get does not call ls_secret_verify. In ls_secret_ensure, if a secret exists, it calls ls_secret_get directly without verifying the HMAC. Only the CLI get wrapper (line 2360) and export command (line 1985) verify HMAC integrity.
- Impact:
Callers sourcing littlesecrets.sh as a library or using `littlesecrets ensure` receive unverified and potentially tampered secret values.
- Remediation:
Embed HMAC verification directly inside ls_secret_get when the hmac option is enabled so all code paths benefit from integrity verification.
