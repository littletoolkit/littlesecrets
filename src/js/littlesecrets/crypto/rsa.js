import { AsmCrypto } from "../crypto.js";
import { PubKey, PrivKey } from "../model.js";

/**
 * RSA implementation of asymmetric cryptography
 */
class AsmCryptoRSA extends AsmCrypto {
  constructor() {
    super();
    this.name = "rsa";
  }

  /**
   * Convert CryptoKey to raw format
   * @param {CryptoKey} key
   * @returns {Promise<Uint8Array>}
   */
  async exportKey(key) {
    const format = key.type === "private" ? "pkcs8" : "spki";
    const exported = await crypto.subtle.exportKey(format, key);
    return new Uint8Array(exported);
  }

  /**
   * Import public key from raw format
   * @param {Uint8Array} keyData
   * @returns {Promise<CryptoKey>}
   */
  async importPublicKey(keyData) {
    return await crypto.subtle.importKey(
      "spki",
      keyData,
      {
        name: "RSA-OAEP",
        hash: "SHA-256",
      },
      true,
      ["encrypt"]
    );
  }

  /**
   * Import private key from raw format
   * @param {Uint8Array} keyData
   * @returns {Promise<CryptoKey>}
   */
  async importPrivateKey(keyData) {
    return await crypto.subtle.importKey(
      "pkcs8",
      keyData,
      {
        name: "RSA-OAEP",
        hash: "SHA-256",
      },
      true,
      ["decrypt"]
    );
  }

  /**
   * @inheritdoc
   */
  async aenc(data, pubKey) {
    const key = await this.importPublicKey(pubKey.data);
    const encrypted = await crypto.subtle.encrypt(
      { name: "RSA-OAEP" },
      key,
      data
    );
    return new Uint8Array(encrypted);
  }

  /**
   * @inheritdoc
   */
  async adec(encData, privKey) {
    const key = await this.importPrivateKey(privKey.data);
    const decrypted = await crypto.subtle.decrypt(
      { name: "RSA-OAEP" },
      key,
      encData
    );
    return new Uint8Array(decrypted);
  }

  /**
   * @inheritdoc
   */
  async generateKeyPair() {
    const keyPair = await crypto.subtle.generateKey(
      {
        name: "RSA-OAEP",
        modulusLength: 3072, // Future-proof key size
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-256",
      },
      true,
      ["encrypt", "decrypt"]
    );

    const pubKeyData = await this.exportKey(keyPair.publicKey);
    const privKeyData = await this.exportKey(keyPair.privateKey);

    return {
      pub: new PubKey(this.name, pubKeyData),
      priv: new PrivKey(this.name, privKeyData),
    };
  }
  /**
   * Detect key format from content
   * @param {Uint8Array} data
   * @returns {'pem'|'der'|'ssh'}
   */
  static DetectFormat(data) {
    // Check if it's PEM format (starts with -----BEGIN)
    const textDecoder = new TextDecoder();
    const text = textDecoder.decode(data.slice(0, 20));
    if (text.startsWith("-----BEGIN")) {
      return "pem";
    }

    // Check if it's SSH format (starts with ssh-rsa or ecdsa-sha2)
    if (text.startsWith("ssh-rsa") || text.startsWith("ecdsa-sha2")) {
      return "ssh";
    }

    // Assume DER format by default
    return "der";
  }

  /**
   * Convert PEM to DER format
   * @param {Uint8Array} pemData
   * @returns {Uint8Array}
   */
  static PemToDer(pemData) {
    const textDecoder = new TextDecoder();
    const pemString = textDecoder.decode(pemData);
    const base64 = pemString
      .replace(/-----BEGIN.*?-----/, "")
      .replace(/-----END.*?-----/, "")
      .replace(/\s+/g, "");
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  }

  /**
   * Convert SSH public key to SPKI format
   * @param {Uint8Array} sshData
   * @returns {Uint8Array}
   */
  static SshToSpki(sshData) {
    const textDecoder = new TextDecoder();
    const sshKey = textDecoder.decode(sshData);

    // Remove any comments and get just the base64 part
    const base64Data = sshKey.split(" ")[1];
    if (!base64Data) {
      throw new Error("Invalid SSH key format");
    }

    // Decode base64 to get raw key components
    const rawKey = Uint8Array.from(atob(base64Data), (c) => c.charCodeAt(0));

    // Parse SSH key format:
    // [length][type][length][exponent][length][modulus]
    let offset = 0;

    // Skip key type
    const typeLen = new DataView(rawKey.buffer).getUint32(0);
    offset = 4 + typeLen;

    // Get exponent
    const expLen = new DataView(rawKey.buffer).getUint32(offset);
    offset += 4;
    const exponent = rawKey.slice(offset, offset + expLen);
    offset += expLen;

    // Get modulus
    const modLen = new DataView(rawKey.buffer).getUint32(offset);
    offset += 4;
    const modulus = rawKey.slice(offset, offset + modLen);

    // Construct SPKI structure
    // RSA Public Key format (ASN.1)
    const rsaPublicKey = new Uint8Array([
      0x30,
      0x82,
      0x00,
      0x00, // SEQUENCE header (length to be filled)
      0x02,
      0x82,
      0x00,
      0x00, // INTEGER (modulus) header
      ...modulus,
      0x02,
      0x03, // INTEGER (exponent) header
      ...exponent,
    ]);

    // Update SEQUENCE length
    const totalLen = rsaPublicKey.length - 4;
    rsaPublicKey[2] = (totalLen >> 8) & 0xff;
    rsaPublicKey[3] = totalLen & 0xff;

    // Update modulus length
    const modBytes = modulus.length;
    rsaPublicKey[6] = (modBytes >> 8) & 0xff;
    rsaPublicKey[7] = modBytes & 0xff;

    // SPKI format wrapping
    const spkiHeader = new Uint8Array([
      0x30,
      0x82,
      0x00,
      0x00, // SEQUENCE header
      0x30,
      0x0d, // SEQUENCE (algorithm)
      0x06,
      0x09, // OBJECT IDENTIFIER
      0x2a,
      0x86,
      0x48,
      0x86, // 1.2.840.113549
      0xf7,
      0x0d,
      0x01,
      0x01, // .1.1.1
      0x01, // (rsaEncryption)
      0x05,
      0x00, // NULL
      0x03,
      0x82,
      0x00,
      0x00, // BIT STRING header
    ]);

    const spki = new Uint8Array([...spkiHeader, ...rsaPublicKey]);

    // Update outer SEQUENCE length
    const spkiLen = spki.length - 4;
    spki[2] = (spkiLen >> 8) & 0xff;
    spki[3] = spkiLen & 0xff;

    // Update BIT STRING length
    const bitStringLen = rsaPublicKey.length;
    spki[spkiHeader.length - 2] = (bitStringLen >> 8) & 0xff;
    spki[spkiHeader.length - 1] = bitStringLen & 0xff;

    return spki;
  }

  /**
   * @inheritdoc
   */
  async pubKey(format, data) {
    let derData;

    switch (format.toLowerCase()) {
      case "pem":
        derData = AsmCryptoRSA.PemToDer(data);
        break;
      case "ssh":
        derData = AsmCryptoRSA.SshToSpki(data);
        break;
      case "der":
        derData = data;
        break;
      default:
        throw new Error(
          `Unsupported key format: ${format} (detected: ${AsmCryptoRSA.DetectFormat(
            data
          )})`
        );
    }

    // Import to validate and normalize
    await this.importPublicKey(derData);
    return new PubKey(this.name, derData);
  }

  /**
   * @inheritdoc
   */
  async privKey(format, data) {
    let derData;

    switch (format.toLowerCase()) {
      case "pem":
        derData = AsmCryptoRSA.PemToDer(data);
        break;
      case "der":
        derData = data;
        break;
      default:
        throw new Error(`Unsupported key format: ${format}`);
    }

    // Import to validate and normalize
    await this.importPrivateKey(derData);
    return new PrivKey(this.name, derData);
  }

  /**
   * @inheritdoc
   */
  async loadPubKey(path) {
    const file = Bun.file(path);
    const data = new Uint8Array(await file.arrayBuffer());
    const format = AsmCryptoRSA.DetectFormat(data);
    return this.pubKey(format, data);
  }

  /**
   * @inheritdoc
   */
  async loadPrivKey(path) {
    const file = Bun.file(path);
    const data = new Uint8Array(await file.arrayBuffer());
    const format = AsmCryptoRSA.DetectFormat(data);
    return this.privKey(format, data);
  }

  /**
   * @inheritdoc
   */
  async makePubKey(privKey) {
    // Import the private key
    const key = await this.importPrivateKey(privKey.data);
    // Extract the public key components
    const pubKey = await crypto.subtle.exportKey("spki", key);
    return new PubKey(this.name, new Uint8Array(pubKey));
  }

  /**
   * @inheritdoc
   */
  async makePrivKey() {
    const keyPair = await crypto.subtle.generateKey(
      {
        name: "RSA-OAEP",
        modulusLength: 3072,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-256",
      },
      true,
      ["encrypt", "decrypt"]
    );
    const privKeyData = await this.exportKey(keyPair.privateKey);
    return new PrivKey(this.name, privKeyData);
  }

  /**
   * @inheritdoc
   */
  async savePubKey(path, pubKey) {
    try {
      // Convert to PEM format
      const spki = pubKey.data;
      const b64 = btoa(String.fromCharCode(...spki));
      const pem = [
        "-----BEGIN PUBLIC KEY-----",
        ...b64.match(/.{1,64}/g),
        "-----END PUBLIC KEY-----",
      ].join("\n");

      await Bun.write(path, pem);
      return true;
    } catch (error) {
      console.error("Failed to save public key:", error);
      return false;
    }
  }

  /**
   * @inheritdoc
   */
  async savePrivKey(path, privKey) {
    try {
      // Convert to PEM format
      const pkcs8 = privKey.data;
      const b64 = btoa(String.fromCharCode(...pkcs8));
      const pem = [
        "-----BEGIN PRIVATE KEY-----",
        ...b64.match(/.{1,64}/g),
        "-----END PRIVATE KEY-----",
      ].join("\n");

      await Bun.write(path, pem);
      return true;
    } catch (error) {
      console.error("Failed to save private key:", error);
      return false;
    }
  }
}

export { AsmCryptoRSA };
