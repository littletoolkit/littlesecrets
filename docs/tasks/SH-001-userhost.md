# User host support

We're going to change the way keys are implemented in `src/sh/littlesecrets.sh`.

Currently public keys are only registered for the current user, for instance if `USER=alice`, then their key will be located at `.littlesecrets/user/alice.pubkey`.

However, we should be storing keys per user *and* host, so in our case the key should really be stored, given `HOSTNAME=machine`, `.littlesecrets/user/alice/machine.pubkey`.

Now, to make that change, we'll need to do a few things:

1) Introduce a `LITTLESECRETS_HOST` variables that defaults to `HOSTNAME` and that can be specified by the`--host` option.

2) Whenever we process a `USER` we will to take care of the host as well. To do this, we will first see if user is like `USER@HOSTNAME`, in which case we use the hostname specified in the string, or otherwise we default to `LITTLESECRETS_HOST`.

To implement the above:
- change the `ls_user_name USER?` function to extract the user from its optional USER argument
- add an `ls_user_host USER?` function that does the same for the host
- look for any function that retrieves or registers the key for the current user, and make sure it uses these functions to get the correct user and host.

Some things to ensure:
- When granting, adding a secret, revoking, the secret should be encrypted for each of the registered host keys. You will need to add `ls_user_list_keys USER? HOST?` to support that, and modify all functions that add/grant/revoke, unless the operation is specifically scope to a given host, like `grant secret user@host`
