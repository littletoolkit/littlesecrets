import { AsmCryptoRSA } from "../../src/js/littlesecrets/crypto/rsa.js";

async function generateTestKeys() {
    const crypto = new AsmCryptoRSA();
    
    // Generate keys in different formats
    const formats = ['pem', 'der'];
    
    for (const format of formats) {
        const keyPair = await crypto.generateKeyPair();
        
        await crypto.savePubKey(
            `tests/data/keypair.${format}.pub`,
            keyPair.pub
        );
        
        await crypto.savePrivKey(
            `tests/data/keypair.${format}.priv`,
            keyPair.priv
        );
    }
}

generateTestKeys().catch(console.error);
