const std = @import("std");
const testing = std.testing;
const crypto = @import("crypto");
const model = @import("shared-secrets");
const fs = std.fs;

test "RSA Encryption" {
    const allocator = testing.allocator;
    
    // Create test secret
    const secret = "This is a test secret that needs to be encrypted";
    
    // Generate new keypair
    var priv_key = try crypto.AsmCryptoRSA.makeprivkey(allocator);
    defer allocator.free(priv_key.data);
    
    var pub_key = try crypto.AsmCryptoRSA.makepubkey(allocator, priv_key);
    defer allocator.free(pub_key.data);
    
    // Encrypt with public key
    var encrypted = try crypto.AsmCryptoRSA.aenc(allocator, secret, pub_key.data);
    defer allocator.free(encrypted);
    
    // Decrypt with private key
    var decrypted = try crypto.AsmCryptoRSA.adec(allocator, encrypted, priv_key.data);
    defer allocator.free(decrypted);
    
    // Verify decrypted matches original
    try testing.expectEqualStrings(secret, decrypted);
}

test "Key Format Support" {
    const allocator = testing.allocator;
    const test_dir = "tests/data";
    const formats = [_][]const u8{ "pem", "der", "openssh" };
    
    // Ensure test directory exists
    try fs.cwd().makePath(test_dir);
    
    for (formats) |format| {
        // Generate keypair
        var priv_key = try crypto.AsmCryptoRSA.makeprivkey(allocator);
        defer allocator.free(priv_key.data);
        
        var pub_key = try crypto.AsmCryptoRSA.makepubkey(allocator, priv_key);
        defer allocator.free(pub_key.data);
        
        // Save keys
        const pub_path = try std.fmt.allocPrint(allocator, "{s}/keypair.{s}.pub", .{ test_dir, format });
        defer allocator.free(pub_path);
        
        const priv_path = try std.fmt.allocPrint(allocator, "{s}/keypair.{s}.priv", .{ test_dir, format });
        defer allocator.free(priv_path);
        
        _ = try crypto.AsmCryptoRSA.savepubkey(allocator, pub_path, pub_key);
        _ = try crypto.AsmCryptoRSA.saveprivkey(allocator, priv_path, priv_key);
        
        // Load keys back
        var loaded_pub = try crypto.AsmCryptoRSA.loadpubkey(allocator, pub_path);
        defer allocator.free(loaded_pub.data);
        
        var loaded_priv = try crypto.AsmCryptoRSA.loadprivkey(allocator, priv_path);
        defer allocator.free(loaded_priv.data);
        
        // Test encryption with loaded keys
        const test_secret = "Testing with loaded keys";
        var encrypted = try crypto.AsmCryptoRSA.aenc(allocator, test_secret, loaded_pub.data);
        defer allocator.free(encrypted);
        
        var decrypted = try crypto.AsmCryptoRSA.adec(allocator, encrypted, loaded_priv.data);
        defer allocator.free(decrypted);
        
        try testing.expectEqualStrings(test_secret, decrypted);
    }
}

test "User SSH Keys" {
    const allocator = testing.allocator;
    
    // Try to load user's SSH key
    const home = std.os.getenv("HOME") orelse return error.NoHomeDir;
    const ssh_dir = try std.fmt.allocPrint(allocator, "{s}/.ssh", .{home});
    defer allocator.free(ssh_dir);
    
    // Common SSH key filenames
    const key_files = [_][]const u8{
        "id_rsa",
        "id_ed25519",
    };
    
    for (key_files) |key_file| {
        const priv_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ ssh_dir, key_file });
        defer allocator.free(priv_path);
        
        const pub_path = try std.fmt.allocPrint(allocator, "{s}/{s}.pub", .{ ssh_dir, key_file });
        defer allocator.free(pub_path);
        
        // Skip if keys don't exist
        if (fs.cwd().access(priv_path, .{})) |_| {
            if (fs.cwd().access(pub_path, .{})) |_| {
                // Load keys
                var priv_key = try crypto.AsmCryptoRSA.loadprivkey(allocator, priv_path);
                defer allocator.free(priv_key.data);
                
                var pub_key = try crypto.AsmCryptoRSA.loadpubkey(allocator, pub_path);
                defer allocator.free(pub_key.data);
                
                // Test encryption
                const test_secret = "Testing with user SSH keys";
                var encrypted = try crypto.AsmCryptoRSA.aenc(allocator, test_secret, pub_key.data);
                defer allocator.free(encrypted);
                
                var decrypted = try crypto.AsmCryptoRSA.adec(allocator, encrypted, priv_key.data);
                defer allocator.free(decrypted);
                
                try testing.expectEqualStrings(test_secret, decrypted);
            } else |_| {}
        } else |_| {}
    }
}
