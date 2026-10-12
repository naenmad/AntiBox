import Foundation

/// Secure local credential vault for AntiBox
/// Stores account refresh tokens and keys in private Application Support storage
/// with restricted POSIX permissions (0600) to eliminate annoying macOS Keychain password prompts.
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let credentialsFile: URL
    private let lock = NSLock()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AntiBox", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        self.credentialsFile = dir.appendingPathComponent("credentials.json")
    }

    public enum KeychainError: LocalizedError {
        case itemNotFound
        case conversionError

        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Credential not found."
            case .conversionError:
                return "Failed to encode/decode credential data."
            }
        }
    }

    private func readAll() -> [String: String] {
        guard FileManager.default.fileExists(atPath: credentialsFile.path),
              let data = try? Data(contentsOf: credentialsFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func writeAll(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: credentialsFile, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsFile.path)
    }

    /// Stores or updates a token for a specific account identifier
    @discardableResult
    public func save(token: String, forAccount accountId: UUID) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var dict = readAll()
        dict[accountId.uuidString] = token
        writeAll(dict)
        return true
    }

    /// Retrieves a token for a specific account identifier
    public func retrieve(forAccount accountId: UUID) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let dict = readAll()
        guard let token = dict[accountId.uuidString], !token.isEmpty else {
            throw KeychainError.itemNotFound
        }
        return token
    }

    /// Deletes credentials for a specific account identifier
    @discardableResult
    public func delete(forAccount accountId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var dict = readAll()
        guard dict.removeValue(forKey: accountId.uuidString) != nil else {
            return false
        }
        writeAll(dict)
        return true
    }

    /// Clears all stored credentials
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: credentialsFile)
    }
}
