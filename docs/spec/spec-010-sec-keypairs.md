# Normalized keypairs

LittleSecrets uses `ls_{privkey,pubkey}_path` and the underlying
`ls_ssh_keypair_ensure` to either convert or create a keypair from an existing
SSH RSA public key.

The process is now like so:

- `LITTLESECRETS_KEY` defines the location of the SSH private key to use, which
  can be overriden with `-k|--key`
- `ls_ssh_keypair_ensure` will derive keys like `littlesecrets-$KEY_ID.pem[.pub]`
  from the `LITTLESECRETS_KEY`, in the same directory, if not available.
- These derived keys will be `400` so that they're readonly and only accessible
  to the user.



