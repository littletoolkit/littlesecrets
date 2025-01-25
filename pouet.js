import {
  createKeyPair,
  exportKey,
  encryptAsym,
  decryptAsym,
  saveKey,
} from "@littlesecrets/crypto.js";
import { str } from "@littlesecrets/utils/text.js";

const keypair = await createKeyPair();
console.log(
  str(await decryptAsym(keypair, await encryptAsym(keypair, "Hello, World!")))
);

console.log(await exportKey(keypair.pubKey));
console.log(await exportKey(keypair.privKey));

// TODO: Should test that the crypto is compatible with the pure bash version
await saveKey(keypair, "testkey");
