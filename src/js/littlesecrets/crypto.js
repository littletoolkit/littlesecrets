/**
 * Interface for asymmetric cryptography operations
 */
class AsmCrypto {
    /** @type {string} */
    name;

    /**
     * Asymmetrically encrypt data with a public key
     * @param {Uint8Array} data Data to encrypt
     * @param {import('./model.js').PubKey} pubKey Public key
     * @returns {Promise<Uint8Array>} Encrypted data
     */
    async aenc(data, pubKey) {
        throw new Error("Not implemented");
    }

    /**
     * Asymmetrically decrypt data with a private key
     * @param {Uint8Array} encData Encrypted data
     * @param {import('./model.js').PrivKey} privKey Private key
     * @returns {Promise<Uint8Array>} Decrypted data
     */
    async adec(encData, privKey) {
        throw new Error("Not implemented");
    }

    /**
     * Generate a new keypair
     * @returns {Promise<{pub: import('./model.js').PubKey, priv: import('./model.js').PrivKey}>}
     */
    async generateKeyPair() {
        throw new Error("Not implemented");
    }

    /**
     * Create a normalized PubKey from key data in the given format
     * @param {string} format Key format (e.g. 'pem', 'der', 'ssh')
     * @param {Uint8Array} data Key data
     * @returns {Promise<import('./model.js').PubKey>}
     */
    async pubKey(format, data) {
        throw new Error("Not implemented");
    }

    /**
     * Create a normalized PrivKey from key data in the given format
     * @param {string} format Key format (e.g. 'pem', 'der')
     * @param {Uint8Array} data Key data
     * @returns {Promise<import('./model.js').PrivKey>}
     */
    async privKey(format, data) {
        throw new Error("Not implemented");
    }

    /**
     * Load a public key from a file, detecting its format
     * @param {string} path Path to key file
     * @returns {Promise<import('./model.js').PubKey>}
     */
    async loadPubKey(path) {
        throw new Error("Not implemented");
    }

    /**
     * Load a private key from a file, detecting its format
     * @param {string} path Path to key file
     * @returns {Promise<import('./model.js').PrivKey>}
     */
    async loadPrivKey(path) {
        throw new Error("Not implemented");
    }

    /**
     * Generate public key from private key
     * @param {import('./model.js').PrivKey} privKey Private key
     * @returns {Promise<import('./model.js').PubKey>}
     */
    async makePubKey(privKey) {
        throw new Error("Not implemented");
    }

    /**
     * Generate new private key
     * @returns {Promise<import('./model.js').PrivKey>}
     */
    async makePrivKey() {
        throw new Error("Not implemented");
    }

    /**
     * Save public key to file in normalized format
     * @param {string} path File path
     * @param {import('./model.js').PubKey} pubKey Public key
     * @returns {Promise<boolean>}
     */
    async savePubKey(path, pubKey) {
        throw new Error("Not implemented");
    }

    /**
     * Save private key to file in normalized format
     * @param {string} path File path
     * @param {import('./model.js').PrivKey} privKey Private key
     * @returns {Promise<boolean>}
     */
    async savePrivKey(path, privKey) {
        throw new Error("Not implemented");
    }
}

export { AsmCrypto };
