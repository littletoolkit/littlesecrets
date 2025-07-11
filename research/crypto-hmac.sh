# We're going to use AEC-GCM as  the encryption format

SECRET="Hello, World!"

SECRET_KEY=$(openssl rand -hex 32)
MAC_KEY=$(openssl rand -hex 32)

# Generate a 12-byte (96-bit) IV (standard for GCM mode)
SECRET_IV=$(openssl rand -hex 16)

# TODO: We could use the `-binary` option in HMAC instead to store the raw output
SECRET_ENC=$(echo -n "$SECRET" | openssl aes-256-cbc -md sha512 -salt -pbkdf2 -K "$SECRET_KEY" -iv "$SECRET_IV" -in /dev/stdin -out /dev/stdout)
SECRET_ENC_HMAC=$(echo -n "$SECRET" | openssl dgst -sha256 -hmac "$(printf '%s' "$SECRET_KEY")")

SECRET_DEC=$(echo -n "$SECRET_ENC" | openssl aes-256-cbc -d -md sha512 -salt -pbkdf2 -K "$SECRET_KEY" -iv "$SECRET_IV" -in /dev/stdin -out /dev/stdout)
SECRET_DEC_HMAC=$(echo -n "$SECRET_DEC" | openssl dgst -sha256 -hmac "$(printf '%s' "$SECRET_KEY")")

echo "$SECRET_DEC_HMAC"
if [ "$SECRET_ENC_HMAC" == "$SECRET_DEC_HMAC" ]; then
	echo "OK: $SECRET_DEC"
else
	echo "TAMPERED: Message have been tampered."
fi
# EOF
