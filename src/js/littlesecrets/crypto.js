import { KeyPair, PubKey, PrivKey } from "./model.js";
import { assertType, assertExists } from "./utils/assert.js";
import { str, bytes } from "./utils/text.js";
import { mkdtemp, shell } from "./utils/shell.js";

function checkOpenSSL() {
  return str(shell(["openssl", "version"])).split(" ")[2];
}

function checkSSHKeygen() {
  return str(shell(["which", "ssh-keygen"]));
}

async function createKeyPair() {
  const keypair = await crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      modulusLength: 4096, // Key size in bits
      publicExponent: new Uint8Array([1, 0, 1]), // 65537
      hash: "SHA-256",
    },
    true, // extractable
    ["encrypt", "decrypt"] // key usages
  );
  return new KeyPair(
    new PrivKey("pkcs8", keypair.privateKey),
    new PubKey("spki", keypair.publicKey)
  );
}

async function importKey(data, format) {
  if (format === undefined) {
    if (data.indexOf("BEING PRIVATE KEY") !== -1) {
      format = "pkcs8";
    } else if (data.indexOf("BEING PUBLIC KEY") !== -1) {
      format = "spki";
    } else {
      throw new Error("importKey: Unsupported format");
    }
  }
  const is_priv = format === "pkcs8";
  const type = is_priv ? "PRIVATE" : "PUBLIC";
  return new (is_priv ? PrivKey : PubKey)(
    "pkcs8",
    await crypto.subtle.importKey(
      "pkcs8", // Format of the key
      // DER
      Buffer.from(
        data
          .replace(`-----BEGIN ${type} KEY-----`, "")
          .replace(`-----END ${type} KEY-----`, "")
          .replace(/\n/g, ""),
        "base64"
      ),
      {
        name: "RSA-OAEP",
        hash: "SHA-256",
      },
      true, // extractable
      [is_priv ? "decrypt" : "encrypt"] // What this key can do
    )
  );
}

async function exportKey(key) {
  if (key instanceof KeyPair) {
    return {
      pubKey: await exportKey(key.pubKey),
      privKey: await exportKey(key.privKey),
    };
  } else {
    // Export the key to PKCS8 format (PEM)
    const type = key instanceof PrivKey ? "PRIVATE" : "PUBLIC";
    return [
      `-----BEGIN ${type} KEY-----`,
      ...(Buffer.from(await crypto.subtle.exportKey(key.format, key.data))
        .toString("base64")
        .match(/.{1,64}/g) || []),
      `-----END ${type} KEY-----`,
    ].join("\n");
  }
}

async function encryptAsym(pubKey, data) {
  if (pubKey instanceof KeyPair) {
    pubKey = pubKey.pubKey;
  }
  assertType(pubKey, PubKey);
  return await crypto.subtle.encrypt(
    {
      name: "RSA-OAEP",
    },
    pubKey.data,
    bytes(data)
  );
}

async function decryptAsym(privKey, data) {
  if (privKey instanceof KeyPair) {
    privKey = privKey.privKey;
  }
  assertType(privKey, PrivKey);
  return await crypto.subtle.decrypt(
    {
      name: "RSA-OAEP",
    },
    privKey.data,
    bytes(data)
  );
}

async function saveKey(key, name = "keypair") {
  if (key instanceof KeyPair) {
    return {
      privKey: await saveKey(key.privKey),
      pubKey: await saveKey(key.pubKey),
    };
  } else if (key instanceof PubKey) {
    const path = `${name}.pub`;
    await Bun.write(path, await exportKey(key), { mode: 0o644 });
    return path;
  } else if (key instanceof PrivKey) {
    const path = `${name}.priv`;
    await Bun.write(path, await exportKey(key), { mode: 0o600 });
    return path;
  } else {
    throw new Error(
      `[saveKey] Unsupported key type: ${key?.constructor?.name}`
    );
  }
}

async function loadKey(path) {
  if (await Bun.exists(path)) {
    return importKey(await Bun.file(path).text());
  } else {
    return new KeyPair(loadKey(`${path}.priv`), loadKey(`${path}.pub`));
  }
}

export {
  createKeyPair,
  importKey,
  exportKey,
  encryptAsym,
  decryptAsym,
  saveKey,
  loadKey,
};
// EOF
