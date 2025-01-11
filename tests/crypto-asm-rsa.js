import { describe, expect, test } from "bun:test";
import { AsmCryptoRSA } from "../src/js/littlesecrets/crypto/rsa.js";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

describe("RSA Asymmetric Crypto", () => {
    const crypto = new AsmCryptoRSA();
    const testSecret = "This is a secret message for testing encryption";
    const secretData = new TextEncoder().encode(testSecret);

    test("basic encryption/decryption", async () => {
        const keyPair = await crypto.generateKeyPair();
        
        const encrypted = await crypto.aenc(secretData, keyPair.pub);
        expect(encrypted).toBeDefined();
        expect(encrypted.length).toBeGreaterThan(0);
        
        const decrypted = await crypto.adec(encrypted, keyPair.priv);
        expect(decrypted).toBeDefined();
        
        const decryptedText = new TextDecoder().decode(decrypted);
        expect(decryptedText).toBe(testSecret);
    });

    describe("key format support", () => {
        const formats = ['pem', 'der'];
        
        for (const format of formats) {
            test(`${format} format`, async () => {
                const pubPath = `tests/data/keypair.${format}.pub`;
                const privPath = `tests/data/keypair.${format}.priv`;
                
                // Skip if test keys don't exist
                if (!existsSync(pubPath) || !existsSync(privPath)) {
                    console.warn(`Skipping ${format} test - keys not found`);
                    return;
                }

                const pubKey = await crypto.loadPubKey(pubPath);
                const privKey = await crypto.loadPrivKey(privPath);

                const encrypted = await crypto.aenc(secretData, pubKey);
                expect(encrypted).toBeDefined();
                
                const decrypted = await crypto.adec(encrypted, privKey);
                const decryptedText = new TextDecoder().decode(decrypted);
                expect(decryptedText).toBe(testSecret);
            });
        }
    });

    describe("user SSH keys", () => {
        test("local SSH keys", async () => {
            const sshDir = join(homedir(), '.ssh');
            const keyPaths = [
                join(sshDir, 'id_rsa'),
                join(sshDir, 'id_ed25519')
            ];

            for (const privKeyPath of keyPaths) {
                const pubKeyPath = `${privKeyPath}.pub`;
                
                if (!existsSync(privKeyPath) || !existsSync(pubKeyPath)) {
                    console.warn(`Skipping SSH key test - ${privKeyPath} not found`);
                    continue;
                }

                const pubKey = await crypto.loadPubKey(pubKeyPath);
                const privKey = await crypto.loadPrivKey(privKeyPath);

                const encrypted = await crypto.aenc(secretData, pubKey);
                expect(encrypted).toBeDefined();
                
                const decrypted = await crypto.adec(encrypted, privKey);
                const decryptedText = new TextDecoder().decode(decrypted);
                expect(decryptedText).toBe(testSecret);
            }
        });
    });
});
