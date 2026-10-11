import Foundation
import Security

/// Thread-safe Keychain Services wrapper for macOS credentials storage
public final class KeychainManager: Sendable {
    public static let shared = KeychainManager()

    private let serviceName = "com.antibox.credentials"

    private init() {}

    public enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case conversionError
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain."
            case .duplicateItem:
                return "Item already exists in Keychain."
            case .conversionError:
                return "Failed to convert string data to UTF-8."
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) {
                    return "Keychain error: \(message as String) (Status: \(status))"
                }
                return "Keychain error with status code \(status)."
            }
        }
    }

    /// Stores or updates an API token or session cookie for a specific account identifier
    @discardableResult
    public func save(token: String, forAccount accountId: UUID) throws -> Bool {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.conversionError
        }

        let accountKey = accountId.uuidString

        // First check if the item already exists
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            // Update existing entry
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus == errSecSuccess {
                return true
            } else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status == errSecItemNotFound {
            // Insert new entry
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return true
            } else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Retrieves an API token for a specific account identifier
    public func retrieve(forAccount accountId: UUID) throws -> String {
        let accountKey = accountId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.conversionError
        }

        return token
    }

    /// Deletes credentials for a specific account identifier
    @discardableResult
    public func delete(forAccount accountId: UUID) -> Bool {
        let accountKey = accountId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
