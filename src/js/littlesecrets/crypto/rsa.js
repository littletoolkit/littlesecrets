import { AsmCrypto } from '../crypto.js';
import { PubKey, PrivKey } from '../model.js';

/**
 * RSA implementation of asymmetric cryptography
 */
class AsmCryptoRSA extends AsmCrypto {
    constructor() {
        super();
        this.name = 'rsa';
    }

    /**
     * Convert CryptoKey to raw format
     * @param {CryptoKey} key
     * @returns {Promise<Uint8Array>}
     */
    async exportKey(key) {
        const format = key.type === 'private' ? 'pkcs8' : 'spki';
        const exported = await crypto.subtle.exportKey(format, key);
        return new Uint8Array(exported);
    }

    /**
     * Import public key from raw format
     * @param {Uint8Array} keyData
     * @returns {Promise<CryptoKey>}
     */
    async importPublicKey(keyData) {
        return crypto.subtle.importKey(
            'spki',
            keyData,
            {
                name: 'RSA-OAEP',
                hash: 'SHA-256'
            },
            true,
            ['encrypt']
        );
    }

    /**
     * Import private key from raw format
     * @param {Uint8Array} keyData
     * @returns {Promise<CryptoKey>}
     */
    async importPrivateKey(keyData) {
        return crypto.subtle.importKey(
            'pkcs8',
            keyData,
            {
                name: 'RSA-OAEP',
                hash: 'SHA-256'
            },
            true,
            ['decrypt']
        );
    }

    /**
     * @inheritdoc
     */
    async aenc(data, pubKey) {
        const key = await this.importPublicKey(pubKey.data);
        const encrypted = await crypto.subtle.encrypt(
            { name: 'RSA-OAEP' },
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
            { name: 'RSA-OAEP' },
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
                name: 'RSA-OAEP',
                modulusLength: 3072, // Future-proof key size
                publicExponent: new Uint8Array([1, 0, 1]),
                hash: 'SHA-256'
            },
            true,
            ['encrypt', 'decrypt']
        );

        const pubKeyData = await this.exportKey(keyPair.publicKey);
        const privKeyData = await this.exportKey(keyPair.privateKey);

        return {
            pub: new PubKey(this.name, pubKeyData),
            priv: new PrivKey(this.name, privKeyData)
        };
    }
}

export { AsmCryptoRSA };
