import CryptoKit
import Foundation
import os
import Security

/// The key that encrypts pinned clipboard items and the saved clipboard history. It is made once, the first time it is needed, and kept in the
/// login Keychain, where only this app can read it on this Mac. It is read from the Keychain once per launch and
/// kept in memory after that, so later callers never touch the Keychain again.
enum ClipboardKey {
    private static let service = "com.deansasek.library"
    private static let account = "clipboard-key"

    /// The key once it has been read or made. Held under the lock for the whole Keychain call, so concurrent
    /// first callers (the launch load and a pin on the main actor) share one Keychain lookup.
    private static let cache = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)

    /// Returns the stored key, or makes and stores a new one. Throws when the Keychain refuses, so callers never
    /// fall back to saving plain text. A failure is not cached, so a later call tries the Keychain again.
    static func key() throws -> SymmetricKey {
        try cache.withLock { cached in
            if let cached { return cached }
            let key = try loadOrCreate()
            cached = key
            return key
        }
    }

    private static func loadOrCreate() throws -> SymmetricKey {
        if let existing = try read() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        var attributes = query()
        attributes[kSecValueData as String] = fresh.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        // Another copy of the app may have made the key between the read and the add.
        if status == errSecDuplicateItem, let existing = try read() { return existing }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return fresh
    }

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Deletes the stored key, so the next call makes a new one. Pinned items sealed with the old key cannot be read after
    /// this, so the caller removes them too. Used only by the user's Reset Clipboard Key.
    static func reset() {
        cache.withLock { $0 = nil }
        SecItemDelete(query() as CFDictionary)
    }

    /// A key is exactly 32 bytes. Any other stored size is corrupt, so it is never used.
    static func isValidKeyData(_ data: Data) -> Bool {
        data.count == 32
    }

    private static func read() throws -> SymmetricKey? {
        var lookup = query()
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        guard isValidKeyData(data) else { throw CorruptKeyError() }
        return SymmetricKey(data: data)
    }

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain error \(status)" }
    }

    /// The stored item is not a 32-byte key. Pinned items cannot be opened with it, and only a reset replaces it.
    struct CorruptKeyError: Error, CustomStringConvertible {
        var description: String { "The stored clipboard key is not 32 bytes" }
    }
}
