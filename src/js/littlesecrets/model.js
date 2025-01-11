/**
 * @typedef {Object} Device
 * @property {string} name Device name, typically hostname
 */

/**
 * Represents a user in the system
 */
class User {
    /** @type {string} */
    name;
    /** @type {Device[]} */
    devices;
    /** @type {PubKey[]} */
    pubKeys;

    /**
     * @param {string} name User name
     */
    constructor(name) {
        this.name = name;
        this.devices = [];
        this.pubKeys = [];
    }
}

/**
 * Represents a group of users
 */
class Group {
    /** @type {string} */
    name;
    /** @type {User[]} */
    users;

    /**
     * @param {string} name Group name
     */
    constructor(name) {
        this.name = name;
        this.users = [];
    }
}

/**
 * Represents metadata about a secret
 */
class MetaData {
    /** @type {string} */
    format;
    /** @type {boolean} */
    shouldRotate;

    /**
     * @param {string} format Encryption format
     */
    constructor(format) {
        this.format = format;
        this.shouldRotate = false;
    }
}

/**
 * Represents a secret value
 */
class Secret {
    /** @type {'text'|'binary'} */
    format;
    /** @type {Uint8Array} */
    data;
    /** @type {MetaData} */
    metadata;
    /** @type {Key} */
    key;

    /**
     * @param {'text'|'binary'} format Secret format
     * @param {Uint8Array} data Secret payload
     * @param {string} encryptionFormat Encryption format
     */
    constructor(format, data, encryptionFormat) {
        this.format = format;
        this.data = data;
        this.metadata = new MetaData(encryptionFormat);
    }
}

/**
 * Represents a symmetric encryption key
 */
class Key {
    /** @type {string} */
    format;
    /** @type {Uint8Array} */
    data;

    /**
     * @param {string} format Key format
     * @param {Uint8Array} data Key data
     */
    constructor(format, data) {
        this.format = format;
        this.data = data;
    }
}

/**
 * Represents a public key
 */
class PubKey {
    /** @type {string} */
    format;
    /** @type {Uint8Array} */
    data;

    /**
     * @param {string} format Key format (e.g. 'rsa', 'ecdsa')
     * @param {Uint8Array} data Public key data
     */
    constructor(format, data) {
        this.format = format;
        this.data = data;
    }
}

/**
 * Represents a private key
 */
class PrivKey {
    /** @type {string} */
    format;
    /** @type {Uint8Array} */
    data;

    /**
     * @param {string} format Key format (e.g. 'rsa', 'ecdsa')
     * @param {Uint8Array} data Private key data
     */
    constructor(format, data) {
        this.format = format;
        this.data = data;
    }
}

/**
 * Represents an encrypted key
 */
class EnKey {
    /** @type {Uint8Array} */
    data;

    /**
     * @param {Uint8Array} data Encrypted key data
     */
    constructor(data) {
        this.data = data;
    }
}

export {
    User,
    Group,
    Secret,
    MetaData,
    Key,
    PubKey,
    PrivKey,
    EnKey
};
