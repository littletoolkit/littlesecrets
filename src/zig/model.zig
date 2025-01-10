const std = @import("std");

/// Represents a user in the system
pub const User = struct {
    /// The user name, like it appears in $USER
    name: []const u8,
};

/// Represents a group of users
pub const Group = struct {
    /// The group name
    name: []const u8,
};

/// Format of a secret
pub const SecretFormat = enum {
    text,
    binary,
};

/// Represents a value that needs to be kept secret
pub const Secret = struct {
    /// The format of the secret data
    format: SecretFormat,
    /// The actual secret payload
    data: []const u8,
};

/// Metadata associated with a secret
pub const MetaData = struct {
    /// The encryption format used for the secret
    format: []const u8,
    /// Indicates if the secret needs rotation
    shouldRotate: bool,
};

/// Represents a symmetric encryption key
pub const Key = struct {
    /// The encryption key format
    format: []const u8,
    /// The actual key data
    data: []const u8,
};

/// Represents a public key
pub const PubKey = struct {
    /// The key format (e.g. "rsa", "ed25519")
    format: []const u8,
    /// The public key data
    data: []const u8,
};

/// Represents a private key
pub const PrivKey = struct {
    /// The key format (e.g. "rsa", "ed25519") 
    format: []const u8,
    /// The private key data
    data: []const u8,
};

/// Represents a Secret Key encrypted with a user's PubKey
pub const EnKey = struct {
    /// The encrypted key data
    data: []const u8,
};
