--
Id: SEC-07
Title: RSA PKCS#1 v1.5 Padding Instead of RSA-OAEP (HIGH)
Location: src/sh/littlesecrets.sh:1048, 1083
--

ls_encrypt_asym and ls_decrypt_asym invoke openssl pkeyutl without specifying padding parameters:
"$LITTLESECRETS_OPENSSL_BIN" pkeyutl -encrypt -pubin -inkey "$pubkey_path" -in "${secret_path}" -out "$output_path"
By default, OpenSSL pkeyutl uses legacy PKCS#1 v1.5 padding.
- Impact:
PKCS#1 v1.5 padding is vulnerable to Bleichenbacher's chosen-ciphertext padding oracle attacks. Although line 935 in the script mentions OAEP padding overhead, OAEP was not configured.
- Remediation:
Specify OAEP padding explicitly when invoking pkeyutl:
-pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
