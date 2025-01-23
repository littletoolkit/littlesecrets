# Implementing the Asymmetric Crypto Backend

We're going to implement the asymmetric crypto backend in `src/js/littletools/crypto`:

- Start by implementing the AsmCrypto interface in `src/js/littletools/crypto.js`
- Implement AsmCryptoRSA, ensuring a  minimum 3072 bits for future-proofing in `src/js/littletools/crypto/rsa.js`

Now we'd like to add support for loading keys, in the AsmCryptoRSA backend implement:

- `pubKey(format,data)->PubKey` that returns a normalized PubKey from the key data in the given format. If
- `privKey(format,data?)->PrivKey` that returns a normalized PubKey from the key data in the given format
- `loadPubKey(path)->PubKey` uses `pubkey` to load the key at the given path, detecting its format
- `loadPrivKey(path)->PubKey` uses `pubkey` to load the key at the given path, detecting its format

Now let's implement functions to generate keys:

- `makePubKey(privkey)->PubKey` generates the PubKey from the PrivKey
- `makePrivKey()->PrivKey` generates a new PrivKey
- `savePubKey(path,pubkey)->bool` saves the pubkey in a normalized format
- `savePrivKey(path,privkey)->bool` saves the privkey in a normalized format

Now let's write a test case for using the asymmetric encryption backend
in `tests/crypto-asm-rsa.js` with the following tests:

- Encryption: validates the encryption mechanism.
    - Pick a secret string that is not too long
    - Generate a keypair
    - Use the public key to encrypt
    - Use the private key to decrypt
    - Validate the decrypted secret is identical

- Formats: validates the loading from supported key formats.
    - Generate keypairs in all the supported format, serve them as files in `tests/data/keypair.<format>.{pub,priv}`
    - For each keypair, load both keys and apply the Encryption te  st with these keys

- User: tests with the user SSH keys
    - If the user has SSH keys, load them and apply the Encryption test.

In order to run the tests automatically, create a `Makefile` with the `make test`
rule that runs the bun tests on on all the test files in `tests/*.js`.
