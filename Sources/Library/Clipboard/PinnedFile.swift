import CryptoKit
import Foundation

/// The pure part of clipboard.json. It takes the key as an argument, so the checks can use their own key and never
/// touch the Keychain. The file is the JSON of the pinned items, sealed with ChaCha20-Poly1305.
enum PinnedFile {
    /// One pinned item as it is stored.
    struct Clip: Codable {
        var source: String?
        var date: Date
        var representations: [[String: Data]]
    }

    enum Read {
        /// The items, and whether the file was plain JSON from before encryption and must be saved again.
        case clips([Clip], migrated: Bool)
        /// Neither sealed with the key nor plain JSON. With no key, this also means the file is sealed.
        case unreadable
    }

    /// Seals `plain` as nonce + ciphertext + tag.
    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(plain, using: key).combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key)
    }

    /// The bytes to write for these items.
    static func encode(_ clips: [Clip], key: SymmetricKey) throws -> Data {
        try seal(JSONEncoder().encode(clips), key: key)
    }

    /// Opens the file as sealed first, then as plain JSON (a file from before encryption). A file that is neither
    /// is unreadable, and nothing is thrown, so a damaged file cannot crash the app.
    static func read(_ data: Data, key: SymmetricKey?) -> Read {
        let decoder = JSONDecoder()
        if let key, let plain = try? open(data, key: key), let clips = try? decoder.decode([Clip].self, from: plain) {
            return .clips(clips, migrated: false)
        }
        if let clips = try? decoder.decode([Clip].self, from: data) {
            return .clips(clips, migrated: true)
        }
        return .unreadable
    }
}
