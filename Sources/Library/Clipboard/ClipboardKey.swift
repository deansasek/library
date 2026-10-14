import CryptoKit
import Foundation
import Security

/// The key that encrypts pinned clipboard items. It is made once, the first time it is needed, and kept in the
/// login Keychain, where only this app can read it on this Mac.
enum ClipboardKey {
    private static let service = "com.deansasek.library"
    private static let account = "clipboard-key"

    /// Returns the stored key, or makes and stores a new one. Throws when the Keychain refuses, so callers never
    /// fall back to saving plain text.
    static func key() throws -> SymmetricKey {
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

    private static func read() throws -> SymmetricKey? {
        var lookup = query()
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw KeychainError(status: status)
        }
        return SymmetricKey(data: data)
    }

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain error \(status)" }
    }
}
