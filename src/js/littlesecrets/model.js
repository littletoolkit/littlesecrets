class User {
  constructor(name) {
    this.name = name;
    this.devices = [];
    this.pubKeys = [];
  }
}

class Group {
  constructor(name) {
    this.name = name;
    this.users = [];
  }
}

class MetaData {
  constructor(format) {
    this.format = format;
    this.shouldRotate = false;
  }
}

class Secret {
  constructor(format, data, encryptionFormat) {
    this.format = format;
    this.data = data;
    this.metadata = new MetaData(encryptionFormat);
  }
}

// What's that for?
class Key {
  constructor(format, data) {
    this.format = format;
    this.data = data;
  }
}

class PubKey {
  constructor(format, data) {
    this.format = format;
    this.data = data;
  }
}

class PrivKey {
  constructor(format, data) {
    this.format = format;
    this.data = data;
  }
}

class KeyPair {
  constructor(privKey, pubKey) {
    this.privKey = privKey;
    this.pubKey = pubKey;
  }
}

export { User, Group, Secret, MetaData, Key, PubKey, PrivKey, KeyPair };
