import Foundation
import Network
import AppKit

/// Native Google OAuth Sign-In manager for connecting Antigravity accounts via browser popup
@MainActor
public final class OAuthSignInManager: ObservableObject {
    public static let shared = OAuthSignInManager()

    @Published public var isAuthenticating: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var errorMessage: String? = nil

    private var listener: NWListener?
    private let callbackPort: UInt16 = 8922
    private let redirectURI = "http://localhost:8922/oauth-callback"

    private var clientId: String {
        let b64 = "MTA3MTAwNjA2MDU5MS10bWhzc2luMmgyMWxjcmUyMzV2dG9sb2poNGc0MDNlcC5hcHBzLmdvb2dsZXVzZXJjb250ZW50LmNvbQ=="
        guard let data = Data(base64Encoded: b64), let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    private var clientSecret: String {
        let b64 = "R0NDU1BYLUs1OEZXUjQ4NkxkTEoxbUxCOHNYQzR6NnFEQWY="
        guard let data = Data(base64Encoded: b64), let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    public struct OAuthAccountResult: Sendable {
        public let email: String
        public let name: String
        public let refreshToken: String
        public let accessToken: String
    }

    private init() {}

    /// Starts local loopback listener and opens Google Sign-In popup in default browser
    public func startAntigravitySignIn() async throws -> OAuthAccountResult {
        isAuthenticating = true
        errorMessage = nil
        statusMessage = "Opening Google Sign-In..."

        defer {
            stopListener()
            isAuthenticating = false
        }

        let code = try await withCheckedThrowingContinuation { continuation in
            do {
                try startLocalServer(continuation: continuation)
            } catch {
                continuation.resume(throwing: error)
            }
        }

        statusMessage = "Exchanging tokens..."
        return try await exchangeCodeForTokens(code: code)
    }

    private func startLocalServer(continuation: CheckedContinuation<String, Error>) throws {
        stopListener()

        guard let port = NWEndpoint.Port(rawValue: callbackPort) else {
            throw URLError(.badURL)
        }

        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener

        let session = OAuthCallbackSession(continuation: continuation)

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receiveHTTPData(connection: connection, session: session)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.openBrowserForAuthorization()
                }
            case .failed(let error):
                session.resume(throwing: error)
            default:
                break
            }
        }

        listener.start(queue: .main)
    }

    private func openBrowserForAuthorization() {
        let scopes = [
            "openid",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/cclog",
            "https://www.googleapis.com/auth/experimentsandconfigs"
        ].joined(separator: " ")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]

        if let url = components.url {
            statusMessage = "Waiting for Google account approval..."
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func receiveHTTPData(connection: NWConnection, session: OAuthCallbackSession) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            guard let data = data, let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                if let error = error {
                    session.resume(throwing: error)
                }
                return
            }

            // Extract authorization code from GET /oauth-callback?code=...
            if let code = extractCode(from: requestString) {
                // Send success response HTML
                let responseHtml = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Connection: close\r
                \r
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <title>AntiBox - Connected</title>
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0c0e14; color: #fff; display: flex; justify-content: center; align-items: center; height: 90vh; margin: 0; }
                        .card { text-align: center; padding: 36px 40px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.1); border-radius: 18px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
                        h2 { color: #34d399; margin: 0 0 10px; font-size: 20px; font-weight: 600; }
                        p { color: #9ca3af; margin: 0; font-size: 13.5px; line-height: 1.5; }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <h2>Login Berhasil!</h2>
                        <p>Akun Antigravity Anda telah berhasil terhubung ke AntiBox.<br>Anda dapat menutup jendela browser ini.</p>
                    </div>
                </body>
                </html>
                """

                if let responseData = responseHtml.data(using: .utf8) {
                    connection.send(content: responseData, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }

                session.resume(returning: code)
            } else {
                connection.cancel()
            }
        }
    }

    nonisolated private static func extractCode(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let urlPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let components = URLComponents(string: urlPart),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }) else {
            return nil
        }
        return codeItem.value
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    private func exchangeCodeForTokens(code: String) async throws -> OAuthAccountResult {
        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        let bodyString = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")

        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let refreshToken = (json["refresh_token"] as? String) ?? ""

        // Fetch User Info (email & name)
        guard let userinfoUrl = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else {
            throw URLError(.badURL)
        }

        var userinfoReq = URLRequest(url: userinfoUrl)
        userinfoReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (userData, userResp) = try await URLSession.shared.data(for: userinfoReq)
        guard let httpUserResp = userResp as? HTTPURLResponse, httpUserResp.statusCode == 200,
              let userJson = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
              let email = userJson["email"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        let name = (userJson["name"] as? String) ?? email

        return OAuthAccountResult(
            email: email,
            name: name,
            refreshToken: refreshToken,
            accessToken: accessToken
        )
    }
}

private final class OAuthCallbackSession: @unchecked Sendable {
    private let continuation: CheckedContinuation<String, Error>
    private let lock = NSLock()
    private var didResume = false

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning code: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: code)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
    }
}

