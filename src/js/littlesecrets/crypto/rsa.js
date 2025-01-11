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
   * Import public key from raw format (SPKI)
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
   * Convert key using ssh-keygen
   * @param {Uint8Array} keyData Input key data
   * @param {string} inFormat Input format ('PEM'|'SSH')
   * @param {string} outFormat Output format ('PEM'|'SSH') 
   * @returns {Promise<Uint8Array>}
   */
  static async convertKey(keyData, inFormat, outFormat) {
    const tmpDir = await Bun.file("/tmp/littlesecrets").exists() 
      ? "/tmp/littlesecrets"
      : await Bun.write("/tmp/littlesecrets", "");

    const inPath = `${tmpDir}/key.${inFormat.toLowerCase()}`;
    const outPath = `${tmpDir}/key.${outFormat.toLowerCase()}`;

    // Write input key
    await Bun.write(inPath, keyData);

    // Convert using ssh-keygen
    const proc = Bun.spawn(["ssh-keygen", "-f", inPath, "-e", "-m", outFormat], {
      stdout: "pipe",
      stderr: "pipe"
    });
    
    const output = await new Response(proc.stdout).arrayBuffer();
    const error = await new Response(proc.stderr).text();
    
    if (await proc.exited && error) {
      throw new Error(`ssh-keygen failed: ${error}`);
    }

    // Cleanup
    await Bun.write(inPath, "");
    
    return new Uint8Array(output);
  }

  /**
   * Parse SSH public key format and convert to SPKI
   * @param {Uint8Array} sshData
   * @returns {Promise<CryptoKey>}
   */
  async parseSshPublicKey(sshData) {
    const textDecoder = new TextDecoder();
    const sshKey = textDecoder.decode(sshData);
    const [type] = sshKey.split(" ");

    if (!type.startsWith("ssh-rsa")) {
      throw new Error("Only RSA SSH keys are supported");
    }

    // Convert SSH to PEM using ssh-keygen
    const pemData = await AsmCryptoRSA.convertKey(sshData, "SSH", "PEM");
    
    // Import the PEM format
    return await crypto.subtle.importKey(
      "spki",
      pemData,
      {
        name: "RSA-OAEP",
        hash: "SHA-256",
      },
      true,
      ["encrypt"]
    );
  }

  /**
   * @inheritdoc
   */
  async pubKey(format, data) {
    let cryptoKey;

    switch (format.toLowerCase()) {
      case "pem":
        cryptoKey = await crypto.subtle.importKey(
          "spki",
          data,
          {
            name: "RSA-OAEP",
            hash: "SHA-256",
          },
          true,
          ["encrypt"]
        );
        break;
      case "ssh":
        cryptoKey = await this.parseSshPublicKey(data);
        break;
      case "der":
        cryptoKey = await crypto.subtle.importKey(
          "spki",
          data,
          {
            name: "RSA-OAEP",
            hash: "SHA-256",
          },
          true,
          ["encrypt"]
        );
        break;
      default:
        throw new Error(
          `Unsupported key format: ${format} (detected: ${AsmCryptoRSA.DetectFormat(
            data
          )})`
        );
    }

    // Export to normalized SPKI format
    const exported = await crypto.subtle.exportKey("spki", cryptoKey);
    return new PubKey(this.name, new Uint8Array(exported));
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
