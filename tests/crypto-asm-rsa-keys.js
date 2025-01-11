import { describe, expect, test } from "bun:test";
import { AsmCryptoRSA } from "../src/js/littlesecrets/crypto/rsa.js";
import { readFileSync } from "node:fs";

describe("RSA Key Format Conversions", () => {
    const crypto = new AsmCryptoRSA();

    describe("SSH Public Key", () => {
        test("parse SSH RSA public key", async () => {
            // Create a test SSH public key
            const sshKeyContent = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0g+ZTxC7weoIJLUafOgrm+h";
            
            const textEncoder = new TextEncoder();
            const keyData = textEncoder.encode(sshKeyContent);
            
            const pubKey = await crypto.pubKey("ssh", keyData);
            expect(pubKey).toBeDefined();
            expect(pubKey.format).toBe("rsa");
            expect(pubKey.data).toBeInstanceOf(Uint8Array);
        });

        test("reject non-RSA SSH keys", async () => {
            const sshKeyContent = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY=";
            const textEncoder = new TextEncoder();
            const keyData = textEncoder.encode(sshKeyContent);
            
            await expect(crypto.pubKey("ssh", keyData)).rejects.toThrow("Only RSA SSH keys are supported");
        });
    });

    describe("PEM Format", () => {
        test("parse PEM public key", async () => {
            const pemContent = `-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtIPmU8Qu8HqCCS1GnzoK
5voX7kNQm8HKtmxcKcTAv68GMet2XosFWHgaLGgKhPtRqHkQ8iLzPeGXihBvBjgV
-----END PUBLIC KEY-----`;
            
            const textEncoder = new TextEncoder();
            const keyData = textEncoder.encode(pemContent);
            
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
