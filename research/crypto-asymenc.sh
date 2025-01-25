source "$(dirname "$(dirname $(realpath "${BASH_SOURCE[0]}"))")"/tests/lib-testing.sh

# --
# Exercises the encryption and decryption
test-start

test-log "Generating RSA keypair using OpenSSL"
KEYSPATH=$(mktemp -d -t littlesecrets.XXX.keys)
PRIVATE_KEY_PATH=$KEYSPATH/keypair.priv # BEGIN PRIVATE KEY
PUBLIC_KEY_PATH=$KEYSPATH/keypair.pub   # BEGIN PUBLIC KEY
SECRET_PATH=$KEYSPATH/secret.raw   # BEGIN PUBLIC KEY
test-run "openssl genrsa -out ""$PRIVATE_KEY_PATH"" 4096"
test-run "openssl rsa -in ""$PRIVATE_KEY_PATH"" -pubout -out ""$PUBLIC_KEY_PATH"" 2> /dev/null"


# NOTE: We go through a file as otherwise the piping to a variable will mangle the result
TEXT="HelloWorld"
test-run "echo -n ""$TEXT"" | openssl pkeyutl -encrypt -pubin -inkey ""$PUBLIC_KEY_PATH"" -in /dev/stdin -out ""$SECRET_PATH"
DECODED=$(openssl pkeyutl -decrypt -inkey "$PRIVATE_KEY_PATH" -in "$SECRET_PATH" -out /dev/stdout)

test-log "TEXT: $TEXT"
test-log "DECODED: $DECODED"
test-expect "$DECODED" "$TEXT"
# EOF

