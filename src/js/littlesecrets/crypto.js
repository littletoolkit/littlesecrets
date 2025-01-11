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
}

export { AsmCrypto };
