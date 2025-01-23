import { describe, expect, test } from "bun:test";
import { AsmCryptoRSA } from "../src/js/littlesecrets/crypto/rsa.js";

const SSH_SAMPLE_PUBKEY = await Bun.file("tests/data/testkey.rsa.pub").bytes();
const SSH_SAMPLE_PUBKEY_PKCS8 = await Bun.file(
  "tests/data/testkey.rsa.pub.pem"
).bytes();
const SSH_SAMPLE_PRIVKEY = await Bun.file(
  "tests/data/testkey.rsa.priv"
).bytes();

describe("RSA Key Format Conversions", () => {
  const crypto = new AsmCryptoRSA();

  describe("SSH Public Key", () => {
    test("parse SSH RSA public key", async () => {
      // Create a test SSH public key
      const keyData = SSH_SAMPLE_PUBKEY;

      const pubKey = await crypto.pubKey("ssh", keyData);
      expect(pubKey).toBeDefined();
      expect(pubKey.format).toBe("rsa");
      expect(pubKey.data).toBeInstanceOf(Uint8Array);
    });

    test("reject non-RSA SSH keys", async () => {
      const sshKeyContent =
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY=";
      const textEncoder = new TextEncoder();
      const keyData = textEncoder.encode(sshKeyContent);

      await expect(crypto.pubKey("ssh", keyData)).rejects.toThrow(
        "Only RSA SSH keys are supported"
      );
    });
  });

  describe("PEM Format", () => {
    test("parse PEM public key", async () => {
      const keyData = SSH_SAMPLE_PUBKEY_PKCS8;

      const pubKey = await crypto.pubKey("pem", keyData);
      expect(pubKey).toBeDefined();
      expect(pubKey.format).toBe("rsa");
      expect(pubKey.data).toBeInstanceOf(Uint8Array);
    });
  });

  describe("Format Detection", () => {
    test("detect PEM format", () => {
      const pemData = new TextEncoder().encode("-----BEGIN PUBLIC KEY-----\n");
      expect(AsmCryptoRSA.DetectFormat(pemData)).toBe("pem");
    });

    test("detect SSH format", () => {
      const sshData = new TextEncoder().encode("ssh-rsa AAAA...");
      expect(AsmCryptoRSA.DetectFormat(sshData)).toBe("ssh");
    });

    test("detect DER format", () => {
      const derData = new Uint8Array([0x30, 0x82]); // Some arbitrary binary data
      expect(AsmCryptoRSA.DetectFormat(derData)).toBe("der");
    });
  });
});
