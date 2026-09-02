--
Id: SEC-13
Title: Forced Passphrase-less SSH Private Keys (MEDIUM)
Location: src/sh/littlesecrets.sh:609–619
--

In ls_ssh_keypair_ensure:
if ! ssh-keygen -y -P "" -f "$privkey_path" >/dev/null 2>&1; then
    ls_log_error "SSH private key with passphrase are not supported: $privkey_path"
    ...
The script rejects SSH private keys protected by a passphrase and generates new keys with empty passphrases (-N "").
- Impact:
Users are forced to use unencrypted private keys on disk, increasing the risk of key compromise if a workstation, home directory, or backup is accessed.
- Remediation:
Support passphrase-protected keys by integrating with ssh-agent or prompting for the passphrase securely when needed.
