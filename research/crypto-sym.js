// Utility function to convert between strings and array buffers
const encoder = new TextEncoder();
const decoder = new TextDecoder();

/**
 * Generates a secure AES-256 key
 * @returns {Promise<CryptoKey>}
 */
async function genkey() {
	return await crypto.subtle.generateKey(
		{
			name: "AES-GCM",
			length: 256,
		},
		true, // extractable
		["encrypt", "decrypt"]
	);
}

/**
 * Encrypts a string value using the provided key
 * @param {string} value - The string to encrypt
 * @param {CryptoKey} key - The AES-GCM key
 * @returns {Promise<string>} Base64 encoded encrypted data
 */
async function encrypt(value, key) {
	// Generate random IV
	const iv = crypto.getRandomValues(new Uint8Array(12));

	// Encrypt the data
	const encodedValue = encoder.encode(value);
	const encryptedData = await crypto.subtle.encrypt(
		{
			name: "AES-GCM",
			iv,
		},
		key,
		encodedValue
	);

	// Combine IV and encrypted data and convert to base64
	const result = new Uint8Array([...iv, ...new Uint8Array(encryptedData)]);
	return btoa(String.fromCharCode(...result));
}

/**
 * Decrypts an encrypted string using the provided key
 * @param {string} encryptedValue - Base64 encoded encrypted data
 * @param {CryptoKey} key - The AES-GCM key
 * @returns {Promise<string>} Decrypted string
 */
async function decrypt(encryptedValue, key) {
	// Convert base64 to Uint8Array
	const encryptedData = Uint8Array.from(atob(encryptedValue), c => c.charCodeAt(0));

	// Extract IV and encrypted content
	const iv = encryptedData.slice(0, 12);
	const content = encryptedData.slice(12);

	// Decrypt the data
	const decryptedData = await crypto.subtle.decrypt(
		{
			name: "AES-GCM",
			iv,
		},
		key,
		content
	);

	return decoder.decode(decryptedData);
}

// Example usage:
try {
	const key = await genkey();
	const encrypted = await encrypt("Hello, World!", key);
	console.log("Encrypted:", encrypted);

	const decrypted = await decrypt(encrypted, key);
	console.log("Decrypted:", decrypted);
} catch (error) {
	console.error("Error:", error);
}

