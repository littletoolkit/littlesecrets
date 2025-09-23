# Model

## Entities

User: represents a user
- name: the user name, like it appears in the `$USER`

Group: represents a group of users
- name: group name

Device: represents a device used by a user
- name: the device name, typically `$HOSTNAME`

Store: the location where the secrets are stored.
- path: the location of the store, as a filesystem path or URL
- format: the format of the store (it could be file, an archive, a DB, etc)

Secret: represents a value that needs to be kept secret
- format: `text` or `binary`
- data: the payload for the secret

MetaData: represents key/value pairs of string/numbers/bool associated with a secret.
- Format: defines the encryption format used for that secret
- ShouldRotate: set to true after a secret was revoked for at least a user

Key: represents the key used to symmetrically
- format: the encryption key format
- data: the encryption key (secret)

KeyPair: a public and private key
- pub: the public key
- priv: the private key

PubKey: represents a public key in a keypair
- format: key format
- data: the public key data

PrivKey: represents a private key in a keypair
- format: key format
- data: the public key data

EnKey: represents a Secret Key encrypted with a user's PubKey
- data: the key's data.


## Relations

- User has one or more PubKeys.
- User may have many Device
- PubKey may be associated to one Device.

- Store may have many Secrets
- Secret has one and only one Key

## Rules

Secrets:
- Each Secret has one Key that is never stored
- Each Secret has one MetaData that keeps track of its format & status.
- Each Secret has at least one EnKey, so that it can be accessed by at least one user.

EnKeys:
- All EnKey of a Secret have the same format
- Each EnKey has one matching PubKey (with which it was created)

Key Pairs:
- PubKey are stored for each user
- PubKey has a matching PrivKey accessible on the local machine, used to decrypt EnKey

Users & Groups:
- Groups may have many users
- Users may have many groups
