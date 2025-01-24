/**
 * Interface for asymmetric cryptography operations
 */
class AsmCrypto {
  name;

  async aenc(data, pubKey) {
    throw new Error("Not implemented");
  }

  async adec(encData, privKey) {
    throw new Error("Not implemented");
  }

  async pubKey(format, data) {
    throw new Error("Not implemented");
  }

  async privKey(format, data) {
    throw new Error("Not implemented");
  }

  async loadPubKey(path) {
    throw new Error("Not implemented");
  }

  async loadPrivKey(path) {
    throw new Error("Not implemented");
  }

  async makePubKey(privKey) {
    throw new Error("Not implemented");
  }

  async makePrivKey() {
    throw new Error("Not implemented");
  }

  async savePubKey(path, pubKey) {
    throw new Error("Not implemented");
  }

  async makeKeyPair() {
    throw new Error("Not implemented");
  }

  async savePrivKey(path, privKey) {
    throw new Error("Not implemented");
  }
}

export { AsmCrypto };
