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

    /**
     * Detect key format from content
     * @param {Uint8Array} data
     * @returns {'pem'|'der'|'ssh'} 
     */
    static detectFormat(data) {
        // Check if it's PEM format (starts with -----BEGIN)
        const textDecoder = new TextDecoder();
        const text = textDecoder.decode(data.slice(0, 20));
        if (text.startsWith('-----BEGIN')) {
            return 'pem';
        }
        
        // Check if it's SSH format (starts with ssh-rsa or ecdsa-sha2)
        if (text.startsWith('ssh-rsa') || text.startsWith('ecdsa-sha2')) {
            return 'ssh';
        }
        
        // Assume DER format by default
        return 'der';
    }

    /**
     * Convert PEM to DER format
     * @param {Uint8Array} pemData
     * @returns {Uint8Array}
     */
    static pemToDer(pemData) {
        const textDecoder = new TextDecoder();
        const pemString = textDecoder.decode(pemData);
        const base64 = pemString
            .replace(/-----BEGIN.*?-----/, '')
            .replace(/-----END.*?-----/, '')
            .replace(/\s+/g, '');
        return Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    }

    /**
     * Convert SSH public key to SPKI format
     * @param {Uint8Array} sshData
     * @returns {Uint8Array}
     */
    static sshToSpki(sshData) {
        // This is a simplified implementation
        // Real implementation would need to parse SSH key format
        // and construct proper SPKI structure
        throw new Error("SSH format not yet supported");
    }

    /**
     * @inheritdoc
     */
    async pubKey(format, data) {
        let derData;
        
        switch (format.toLowerCase()) {
            case 'pem':
                derData = AsmCryptoRSA.pemToDer(data);
                break;
            case 'ssh':
                derData = AsmCryptoRSA.sshToSpki(data);
                break;
            case 'der':
                derData = data;
                break;
            default:
                throw new Error(`Unsupported key format: ${format}`);
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
            case 'pem':
                derData = this.pemToDer(data);
                break;
            case 'der':
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
        const response = await fetch(path);
        const data = new Uint8Array(await response.arrayBuffer());
        const format = AsmCryptoRSA.detectFormat(data);
        return this.pubKey(format, data);
    }

    /**
     * @inheritdoc
     */
    async loadPrivKey(path) {
        const response = await fetch(path);
        const data = new Uint8Array(await response.arrayBuffer());
        const format = this.detectFormat(data);
        return this.privKey(format, data);
    }
}

export { AsmCryptoRSA };
