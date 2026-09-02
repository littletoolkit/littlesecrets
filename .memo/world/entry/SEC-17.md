--
Id: SEC-17
Title: Orphaned Temporary Secret Key Files on Process Interruption (LOW)
Location: src/sh/littlesecrets.sh:1829
--

In ls_secret_grant:
secret_key_tmp=$(mktemp "${secret_key_path}.tmp.XXXXXX")
This temporary key file is created inside the store's secret directory but is never registered in LS_CLEANUP.
- Impact:
If the grant operation is interrupted (SIGINT, SIGTERM, crash), unencrypted or temporary key files remain on disk in the store directory instead of being cleaned up.
- Remediation:
Register secret_key_tmp in LS_CLEANUP immediately after creation:
LS_CLEANUP+=("$secret_key_tmp")
