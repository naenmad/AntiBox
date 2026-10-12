import Foundation
import SQLite3

/// Independent service that hot-switches the active account in running Antigravity IDE
/// by directly injecting OAuth tokens into state.vscdb and signaling language_server hot reload.
public final class AntigravityIDESyncService: Sendable {
    public static let shared = AntigravityIDESyncService()

    private let ideStatePath: URL
    private let directEngine = DirectCloudCodeEngine.shared
    private let keychain = KeychainManager.shared

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.ideStatePath = appSupport
            .appendingPathComponent("Antigravity IDE", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
    }

    public var isIDEInstalled: Bool {
        FileManager.default.fileExists(atPath: ideStatePath.path)
    }

    /// Reads the currently authenticated account from Antigravity IDE
    public func getActiveIDEAccount() -> (email: String?, name: String?) {
        guard isIDEInstalled else { return (nil, nil) }

        var db: OpaquePointer?
        guard sqlite3_open(ideStatePath.path, &db) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_close(db) }

        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityAuthStatus' LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            let jsonString = String(cString: cStr)
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let email = json["email"] as? String
                let name = json["name"] as? String
                return (email, name)
            }
        }
        return (nil, nil)
    }

    /// Directly switches Antigravity IDE to the specified account
    public func switchToAccount(account: Account) async -> (success: Bool, message: String) {
        guard isIDEInstalled else {
            return (false, "Antigravity IDE installation not detected at ~/Library/Application Support/Antigravity IDE.")
        }

        // 1. Retrieve refresh token
        var refreshToken = (try? keychain.retrieve(forAccount: account.id)) ?? ""

        // Fallback: check ~/.antigravity_tools/accounts/<id>.json
        if refreshToken.isEmpty {
            let toolsFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".antigravity_tools/accounts/\(account.id.uuidString).json")
            if let data = try? Data(contentsOf: toolsFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tokenObj = json["token"] as? [String: Any] {
                refreshToken = (tokenObj["refresh_token"] as? String) ?? ""
            }
        }

        guard !refreshToken.isEmpty else {
            let accountName = account.email.isEmpty ? account.name : account.email
            return (false, "No OAuth credentials found for \(accountName). Please reconnect account.")
        }

        // 2. Fetch fresh Google OAuth access token directly
        let accessToken: String
        do {
            accessToken = try await directEngine.refreshAccessToken(refreshToken: refreshToken)
        } catch {
            return (false, "Failed to refresh Google OAuth token: \(error.localizedDescription)")
        }

        // 3. Build Protobuf base64 string for antigravityUnifiedStateSync.oauthToken
        let oauthTokenB64 = buildProtobufToken(accessToken: accessToken, refreshToken: refreshToken)

        // 4. Build JSON for antigravityAuthStatus
        let authStatusDict: [String: String] = [
            "name": account.name,
            "email": account.email.isEmpty ? account.name : account.email,
            "apiKey": accessToken
        ]
        guard let authStatusData = try? JSONSerialization.data(withJSONObject: authStatusDict),
              let authStatusString = String(data: authStatusData, encoding: .utf8) else {
            return (false, "Failed to serialize IDE auth status.")
        }

        // 5. Open SQLite database and execute injection
        var db: OpaquePointer?
        guard sqlite3_open(ideStatePath.path, &db) == SQLITE_OK else {
            return (false, "Could not open Antigravity IDE state database.")
        }
        defer { sqlite3_close(db) }

        let updateAuthStatus = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityAuthStatus', ?);"
        let updateOAuthToken = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.oauthToken', ?);"
        let clearOnboarding = "DELETE FROM ItemTable WHERE key = 'antigravityOnboardingjetskiStateSync.agentManagerInitState';"

        _ = executeSQL(db: db, sql: updateAuthStatus, bindText: authStatusString)
        _ = executeSQL(db: db, sql: updateOAuthToken, bindText: oauthTokenB64)
        _ = executeSQL(db: db, sql: clearOnboarding, bindText: nil)

        // 6. Update ~/.antigravity_tools/accounts.json current_account_id if present
        updateAntigravityToolsCurrentAccount(id: account.id)

        // 7. Hot-reload: Respawn language_server_macos_arm subprocess
        hotReloadLanguageServer()

        let targetEmail = account.email.isEmpty ? account.name : account.email
        return (true, "Successfully switched Antigravity IDE to \(targetEmail)!")
    }

    // MARK: - Protobuf Encoding

    private func encodeVarint(_ value: Int) -> Data {
        var v = value
        var data = Data()
        while v > 0x7F {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
        return data
    }

    private func encodeLenDelim(tag: Int, bytes: Data) -> Data {
        let key = (tag << 3) | 2
        var res = encodeVarint(key)
        res.append(encodeVarint(bytes.count))
        res.append(bytes)
        return res
    }

    private func encodeString(tag: Int, str: String) -> Data {
        return encodeLenDelim(tag: tag, bytes: Data(str.utf8))
    }

    private func buildProtobufToken(accessToken: String, refreshToken: String) -> String {
        // Inner Token Info Message
        var inner = Data()
        inner.append(encodeString(tag: 1, str: accessToken))
        inner.append(encodeString(tag: 2, str: "Bearer"))
        inner.append(encodeString(tag: 3, str: refreshToken))

        var tag4 = encodeVarint((4 << 3) | 2)
        let expiryBytes = Data([0x08, 0xa0, 0xee, 0xad, 0xd6, 0x06])
        tag4.append(encodeVarint(expiryBytes.count))
        tag4.append(expiryBytes)
        inner.append(tag4)

        let innerB64 = inner.base64EncodedString()

        // oauthTokenInfoSentinelKey submessage
        var tokenSentinel = Data()
        tokenSentinel.append(encodeString(tag: 1, str: "oauthTokenInfoSentinelKey"))
        tokenSentinel.append(encodeString(tag: 2, str: innerB64))

        // authStateWithContextSentinelKey submessage
        let authCtxJson = "{\"state\":\"signedIn\",\"context\":{\"project\":\"\",\"showProjectError\":false,\"errorMessage\":\"\",\"ineligibleMessage\":\"\",\"verificationUrl\":\"\",\"isGcpTos\":false,\"browserOpenFailed\":false,\"appealUrl\":\"\",\"appealLinkText\":\"\"}}"
        var authSentinel = Data()
        authSentinel.append(encodeString(tag: 1, str: "authStateWithContextSentinelKey"))
        authSentinel.append(encodeString(tag: 2, str: authCtxJson))

        // Outer wrapper
        var full = Data()
        full.append(encodeLenDelim(tag: 1, bytes: authSentinel))
        full.append(encodeLenDelim(tag: 1, bytes: tokenSentinel))

        return full.base64EncodedString()
    }

    // MARK: - SQLite Helper

    private func executeSQL(db: OpaquePointer?, sql: String, bindText: String?) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        if let text = bindText {
            sqlite3_bind_text(stmt, 1, (text as NSString).utf8String, -1, nil)
        }

        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - Process Hot Reload

    private func hotReloadLanguageServer() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", "language_server_macos_arm"]
        try? task.run()
    }

    private func updateAntigravityToolsCurrentAccount(id: UUID) {
        let toolsBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".antigravity_tools")
        let accountsFile = toolsBase.appendingPathComponent("accounts.json")
        guard FileManager.default.fileExists(atPath: accountsFile.path),
              let data = try? Data(contentsOf: accountsFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        json["current_account_id"] = id.uuidString.lowercased()
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updatedData.write(to: accountsFile, options: [.atomic])
        }
    }
}
