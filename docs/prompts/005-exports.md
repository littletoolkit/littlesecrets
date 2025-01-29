# Secrets Exports

Exporting secrets is meant to only support a read-only use case. In that regards, only the
`.littlesecrets/secret/` folder is necessary. Additionally, exporting can be limited to only
a subset of secrets and a subset of users. For instance

```
littlesecrets export --secrets "*.production" --user "devops-*" secrets.zip
```

## JSON file

Exporting secrets to a JSON structure, where keys and secrets are base64-encoded.
The JSON structure should be like so:

```
{"<secret.name>":{
  "@":"<encrypted secret in base64>",
  "<user>":"<user encrypted decryption key in base64>"
}
```

## Archive File

Exporting secrets to a zip file (or `tar.gz`, `tar.bz2`) will simply package
all the matching files in the `.littlesecrets` folder.

## SQLite

SQLite should support SQL archive export and updating a database. The process should work like so:

- Ensure that the database contains a `LittleSecretsKeys` table with fields `SecretName`, `SecretUser`, `SecretKeyEnc`, and a `LittleSecrets` table with field `SecretName`, `SecretEnc`. Noting here that `SecretName` is a string id, an encrypted secrets and keys are binary blobs.
- For each matching secret that contains matching user keys, upsert the corresponding values in the `LittleSecretKeys` and `LittleSecrets` tables.

The SQLite export should have a `--clear` option that clears the secrets table before doing an export, in order for secrets not to accumulate.

## AWS Secrets Manager

ASM supports more refined operations, and the process should work like so:

- When a secret does not exist, it is created
- If it exists, it is rotated
- Each secret has an `Origin` tag with `LittleSecrets` as value.
- Secrets permissions are untouched, and expected to be managed by someone else

## AWS DynamoDB

DynamoDB export takes a database name and works like so:

- Ensures a `LittleSecretsKeys` table with `SecretName:str`, `SecretUser:str`, `SecretKeyEnc:binary` where `SecretName` is the primary key and `SecretUser` the secondary key.
- Ensures a `LittleSecrets` table with `SecretName:str`, `SecretEnd:binary` where `SecretName` is the primary key.
- Matching secrets and user keys are upserted
- Export should provide the option to clear the database
