# Filesystem Store

The filesystem store contains encrypted secrets, public keys, and recipient
envelopes. Archive, object-store, and database backends are not implemented.

```
store.id                         # Random identity, pinned locally
secret/
  <name>/
    secret.enc                   # Encrypted value
    secret.hmac                  # Mandatory v1/v2 HMAC tag
    secret.format                # Signed symmetric scheme identifier
    secret.signer                # Signing user@host
    secret.sig                   # Signature of identity and record fields
    <user>@<host>.key             # Identity-bound encrypted master key
user/
  <name>/
    <host>.pubkey                # Normalized RSA public key
```

Names contain ASCII letters, digits, `_`, `-`, and `.`, cannot start with `.` or
`-`, and cannot contain `..`. Symlinks and special entries in store/trust paths
are rejected. Writes enter checked directories and publish staged files by
rename, avoiding direct writes through existing destination entries.

## Local trust

Trust lives outside the shared store at
`${LITTLESECRETS_TRUST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/littlesecrets}`.
Each checkout has a directory named by the SHA-256 digest of its absolute store
path, containing `store.id` and `user/<name>/<host>.pubkey` pins. The trust root
and checkout directory must be owned by the caller and private (mode `0700`).

`init` serializes identity creation and pinning under `.init.lock.d`. It never
replaces an existing identity pin. `register` normalizes an independently
verified public key and writes both the shared registration and local pin.
Registering a replacement key is an explicit trust change. Automatic caller
registration derives a public key from the caller's local private key.

Automatic legacy migration may initialize the store identity and caller's pin
after verifying the old record's HMAC. It also initializes missing recipient
pins from registrations in the accepted Git checkout. Existing identity pins
must still match, and existing recipient pins are retained. Migration leaves
uncommitted changes for Git review.

Reads require a pinned signer key. Grants and automatic writer-host recipients
must match local pins; a key injected into the shared registration directory
is insufficient. Each checkout must establish its own pins. Moving the store
to another path requires establishing pins for that path.

## Operations

- `add`/`set` replaces a record with fresh encryption and envelopes for the
  writer's trusted registered hosts. Other recipients need a subsequent grant.
- `ensure` creates only absent records, checking under the record lock.
- `grant` authenticates the old record and signs the expanded recipient set.
- `revoke` matches actual envelopes, rotates the master key, and writes v2 for
  all remaining pinned recipients, even after a user's deregistration.
- `register` changes a registration and local pin; existing envelopes/signatures
  are not automatically regenerated for a replacement key.
- `deregister` removes shared registrations, retaining local pins and envelopes.
  It does not revoke secret access or invalidate historical signatures.
- Authenticated access automatically migrates unsigned historical records before
  use. `hash` and `verify` leave signed records unchanged. Missing tags fail.

## Transactions and recovery

Each secret uses `secret/.<name>.lock.d`, an atomic mkdir-based cooperative lock.
Only its acquiring process/token can release it. A lock is never stolen based
on its age or PID; abandoned locks require explicit operator recovery.

Writers stage a complete record under `secret/.ls-stage.*`, retain the previous
generation under `.ls-backup.*`, and rename the new directory into place while
holding the lock. Failures roll back when possible; otherwise the backup is
retained and its path reported. Readers take the same lock while copying a
private snapshot, then authenticate and decrypt those copied bytes.

Atomicity is per secret, not across a wildcard operation. A completed automatic
migration can remain even if a later operation fails. This is not a
power-loss/SIGKILL transaction guarantee: interruption can leave a gap, backup,
staging directory, or lock requiring recovery. Other writers, including older
LittleSecrets clients, must not modify the store concurrently outside this
locking protocol. Git operations should run while the store is idle.

Temporary plaintext and keys are mode `0600` inside a process-owned private
directory under `TMPDIR`. Normal exit, SIGINT, and SIGTERM clean up that
directory, including files allocated in command substitutions. SIGKILL and
power loss require manual cleanup. Local account/filesystem compromise and
rollback of an entire previously valid record are outside these guarantees.

Groups and arbitrary secret metadata are not implemented. See
`spec-011-format-v2.md` for the signed representation and migration procedure.
