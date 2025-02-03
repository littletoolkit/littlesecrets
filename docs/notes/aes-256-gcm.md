To use AES-256-GCM in littlesecrets.sh, you need to modify the ls_encrypt_sym and ls_decrypt_sym functions. Here's how you can do it, along with explanations:

```
# --- Encryption with AES-256-GCM ---

function ls_encrypt_sym { # KEY
    local key_path=$(ls_mkstemp "$1")
    local iv=$(openssl rand -base64 12) # Generate a random 96-bit (12-byte) IV
    local tag_path=$(ls_mkstemp)

    ls_log_output_start

    # Encrypt with AES-256-GCM and store the tag
    openssl enc -aes-256-gcm -iv "$iv" -pass "file:$key_path" -in /dev/stdin -out >(ls_encode) -tag -out "$tag_path"

    local res=$?

    ls_log_output_end

    # Output the IV and tag (encoded) after the ciphertext
    echo "$iv" | ls_encode
    cat "$tag_path" | ls_encode

    ls_unlink "$key_path" "$tag_path"
    return "$res"
}



# --- Decryption with AES-256-GCM ---

function ls_decrypt_sym { # KEY
    local key_path=$(ls_mkstemp "$1")
    # Extract ciphertext, IV, and tag from stdin (encoded)
    local ciphertext=$(sed -E 's/@LS://;s/(.{44}).*/\\1/g' | tr -d '\\n' | ls_decode)
    local iv=$(tail -n +2 | head -n 1 | sed -E 's/@LS://g' | tr -d '\\n' | ls_decode)
    local tag=$(tail -n +3 | sed -E 's/@LS://g' | tr -d '\\n' | ls_decode)

    local ciphertext_path=$(ls_mkstemp "$ciphertext")
    local iv_path=$(ls_mkstemp "$iv")
    local tag_path=$(ls_mkstemp "$tag")

    ls_log_output_start

    # Decrypt with AES-256-GCM, verifying the tag
    openssl enc -aes-256-gcm -d -iv "$iv" -pass "file:$key_path" -in "$ciphertext_path" -out /dev/stdout -tag "file:$tag_path"

    local res=$?

    ls_log_output_end

    ls_unlink "$key_path" "$ciphertext_path" "$iv_path" "$tag_path"
    return "$res"
}
```

Key Changes and Explanations:

- IV Generation: A random 12-byte (96-bit) Initialization Vector (IV) is generated using openssl rand -base64 12. This IV is crucial for GCM mode and must be unique for every encryption operation. The IV is then encoded and appended to the output.
Tag Generation and Verification: The -tag option is used with openssl enc to generate and store the authentication tag. During decryption, the -tag option is used to verify the tag.
Encoding and Decoding: The ciphertext, IV, and tag are encoded using ls_encode before being stored or transmitted. During decryption, they are decoded using ls_decode.
Error Handling: The return codes from openssl commands are checked to ensure proper error handling.
Ciphertext, IV, and Tag Handling: The updated functions now handle passing the ciphertext, IV, and tag correctly to the openssl command. The ciphertext is piped to standard input, and the IV and tag are provided as command-line arguments.
Temporary Files: Temporary files are used to store the key, IV, and tag during encryption and decryption. These files are securely deleted afterward.
These modifications ensure that the script now uses AES-256-GCM for symmetric encryption, providing authenticated encryption and significantly improving the security of the stored secrets. Remember to update any other parts of the script that interact with ls_encrypt_sym and ls_decrypt_sym to handle the encoded IV and tag correctly. Specifically, the ls_secret_write and ls_secret_get functions will need adjustments to store and retrieve the IV and tag along with the ciphertext. You'll need to modify how these values are stored within the secret files and how they are passed to the encryption and decryption functions.
