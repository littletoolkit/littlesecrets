# Store

The Secret store is where secrets, public keys and encrypted keys are stored.
The Store is an abstract interface that should support multiple backends, such
as files, an archive, S3, SQLite, etc.

The store uses cryptographic backends, which was defined earlier.

The store is expected to store data in hierarchical fashion, following this structure:

```
secrets/                       # Stores the secrets
  <name>/
    secret.raw                 # Secret, encrypted with its Key
    secret.json                # Secret format and metadata
    <user>.<host>.enkey        # Secret EncKey matching the User & Host PubKey

users/                         # Stores the users
  <name>/                      # User Name
    <host>/                    # User Host
      <keyformat>.pubkey       # User & Host PubKey

groups/                        # Keeps track of groups
  <name>/                      # Group Name
    <user>                     # Member User Name
```

Note that it is important for the store to know when items were updated, as for
instance if a PubKey is updated, all corresponding EnKeys will be invalidated
and will need to be recreated.


The interface is as follows for Secrets:

- `secrets()` lists the secrets available

- `granted(name, user?)` lists secrets granted for a given user (or all users).

- `add(name, secret, user, symformat?, asymformat?)` adds a new secret encrypted with all the registered
   user PubKeys and store it under the given name. The optional `symformat` and `asymformat`
   are used to choose the crypto backends for the secret and EncKeys. The symformat

- `grant(name, secret, fromUser, toUser?)`, `fromUser` grants access to the secret
  to `toUser` (defaulting to `fromUser` if null). Will generate EnKey for the secret
  for each user/host PubKey, only if the EnKey does not exist of is older than the PubKey.

- `update(name, secret, user, symformat?, asymformat?)` updates an existing secret. This should automatically
  grant access to users who already had access to the secret.

- `revoke(name, secret, user)` revokes the secret for the given user, flagging the
  secret as needing rotation (ShouldRotate in MetaData), and removing the EnKey(s) for
  that secret and user.

- `drop(name,secret,user,host)` removes the EnKey for the given secret, user and host,
  if it exists. If the user has not more EnKey for the secret, the secret should
  be marked as ShouldRotate in its MetaData.

- `has(name, secret, user?)` when `user` is null will tell if the secret
  exists, if a user is given will tell if the user has access to the secret.

For User:

- `users()` lists the users and hosts

- `register(user, host, pubkey)` registers a PubKey for a given user and host.
  If the PubKey exists, it will be replaced and all matching EnKey will be
  regenerated then, so that the user keeps access to their secrets.

- `unregister(user, host?, pubkey?)` unregisters the PubKey for a given user and host.
  If `pubkey` is given, it this will only be effective if the pubkey exists and
  is identical for the given host, if no host is given, then this removes

For Groups:

- `groups(user?)` lists all the groups or the groups to which the user belongs to.

- `member(group, user)` tells if the user is a member of the group.

- `join(group,user)` adds the user to the group if not already there, creating
  the group if necessary.

- `leave(group,user?)`  remove the user or all users from the group. If group
  is empty, removes the group.
