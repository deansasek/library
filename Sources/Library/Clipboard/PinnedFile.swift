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

    /// The kind of sealed file. Each kind is sealed with its name as associated data, so a file of one kind does not
    /// open as the other, even with the same key.
    enum Kind: String {
        case pinned
        case history
    }

    /// Seals `plain` as nonce + ciphertext + tag, bound to `kind`.
    static func seal(_ plain: Data, key: SymmetricKey, kind: Kind = .pinned) throws -> Data {
        try ChaChaPoly.seal(plain, using: key, authenticating: Data(kind.rawValue.utf8)).combined
    }

    static func open(_ sealed: Data, key: SymmetricKey, kind: Kind = .pinned) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key, authenticating: Data(kind.rawValue.utf8))
    }

    /// Opens a file sealed before the kinds were told apart, which has no associated data. Such a file is read once,
    /// then saved again with its kind.
    static func openUnbound(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key)
    }

    /// The bytes to write for these items.
    static func encode(_ clips: [Clip], key: SymmetricKey) throws -> Data {
        try seal(JSONEncoder().encode(clips), key: key)
    }

    /// Opens the file as sealed first, then as an older sealed file, then as plain JSON (a file from before encryption).
    /// A file that is none of these is unreadable, and nothing is thrown, so a damaged file cannot crash the app.
    static func read(_ data: Data, key: SymmetricKey?) -> Read {
        let decoder = JSONDecoder()
        if let key, let plain = try? open(data, key: key), let clips = try? decoder.decode([Clip].self, from: plain) {
            return .clips(clips, migrated: false)
        }
        if let key, let plain = try? openUnbound(data, key: key), let clips = try? decoder.decode([Clip].self, from: plain) {
            return .clips(clips, migrated: true)
        }
        if let clips = try? decoder.decode([Clip].self, from: data) {
            return .clips(clips, migrated: true)
        }
        return .unreadable
    }
}
