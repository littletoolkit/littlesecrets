const std = @import("std");
const Allocator = std.mem.Allocator;

/// Interface for asymmetric cryptography operations
pub const AsmCrypto = struct {
    /// Name of the crypto backend
    name: []const u8,

    /// Asymmetrically encrypt data with a public key
    aencFn: *const fn (allocator: Allocator, data: []const u8, pubkey: []const u8) error{TooLarge}![]u8,

    /// Asymmetrically decrypt data with a private key  
    adecFn: *const fn (allocator: Allocator, encdata: []const u8, privkey: []const u8) error{InvalidKey}![]u8,

    /// Encrypt data using this backend
    pub fn aenc(self: *const AsmCrypto, allocator: Allocator, data: []const u8, pubkey: []const u8) ![]u8 {
        return self.aencFn(allocator, data, pubkey);
    }

    /// Decrypt data using this backend
    pub fn adec(self: *const AsmCrypto, allocator: Allocator, encdata: []const u8, privkey: []const u8) ![]u8 {
        return self.adecFn(allocator, encdata, privkey);
    }
};

/// RSA implementation of asymmetric crypto with 3072-bit keys
pub const AsmCryptoRSA = struct {
    const Self = @This();
    const KEY_BITS: usize = 3072;
    const PADDING = std.crypto.rand;

    /// The interface implementation
    pub const interface = AsmCrypto{
        .name = "rsa3072",
        .aencFn = aenc,
        .adecFn = adec,
    };

    /// Encrypt data with RSA public key
    pub fn aenc(allocator: Allocator, data: []const u8, pubkey: []const u8) error{TooLarge}![]u8 {
        // Parse the public key
        var key = try std.crypto.rsa.PublicKey.fromDer(pubkey);
        
        // Check if data is too large for RSA encryption
        const max_size = (KEY_BITS / 8) - 42; // Account for OAEP padding
        if (data.len > max_size) {
            return error.TooLarge;
        }

        // Allocate output buffer
        var out = try allocator.alloc(u8, KEY_BITS / 8);
        errdefer allocator.free(out);

        // Encrypt with OAEP padding
        try key.encrypt(out, data, PADDING);
        
        return out;
    }

    /// Decrypt data with RSA private key
    pub fn adec(allocator: Allocator, encdata: []const u8, privkey: []const u8) error{InvalidKey}![]u8 {
        // Parse the private key
        var key = try std.crypto.rsa.PrivateKey.fromDer(privkey);
        
        // Allocate output buffer - same size as input for RSA
        var out = try allocator.alloc(u8, encdata.len);
        errdefer allocator.free(out);

        // Decrypt with OAEP padding
        const decrypted = try key.decrypt(out, encdata, PADDING);
        
        // Resize buffer to actual decrypted size
        return allocator.realloc(out, decrypted.len);
    }
};
