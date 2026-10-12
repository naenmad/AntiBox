import Foundation

/// Production native engine that communicates directly with Google Cloud Code and AI APIs
/// without requiring Antigravity Tools or any local proxy server.
public final class DirectCloudCodeEngine: Sendable {
    public static let shared = DirectCloudCodeEngine()

    // Public OAuth client metadata decoded at runtime
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

    private let userAgent = "antigravity/1.107.0"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let quotaSummaryEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
    private let availableModelsEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    public struct DirectQuotaResult: Sendable {
        public let geminiWeeklyPercentage: Double
        public let geminiResetDate: Date
        public let thirdPartyWeeklyPercentage: Double
        public let thirdPartyResetDate: Date
        public let imageQuotaPercentage: Double?
        public let imageQuotaResetDate: Date?
        public let models: [QuotaItem]
        public let subscriptionTier: String
    }

    /// Directly refreshes Google OAuth access token using standard OAuth2 refresh_token grant
    public func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: tokenEndpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")

        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return accessToken
    }

    /// Fetches authoritative quota buckets and model list directly from Google Cloud Code API
    public func fetchDirectQuotas(accessToken: String, projectId: String = "aicode-consumers") async throws -> DirectQuotaResult {
        // 1. Query retrieveUserQuotaSummary
        guard let quotaUrl = URL(string: quotaSummaryEndpoint) else {
            throw URLError(.badURL)
        }

        var quotaReq = URLRequest(url: quotaUrl)
        quotaReq.httpMethod = "POST"
        quotaReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        quotaReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        quotaReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let quotaPayload = ["project": projectId]
        quotaReq.httpBody = try? JSONSerialization.data(withJSONObject: quotaPayload)

        let (quotaData, quotaResp) = try await session.data(for: quotaReq)
        guard let httpQuotaResp = quotaResp as? HTTPURLResponse, httpQuotaResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let quotaJson = try? JSONSerialization.jsonObject(with: quotaData) as? [String: Any],
              let groups = quotaJson["groups"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        let isoFormatter = ISO8601DateFormatter()
        var geminiWeeklyPct = 100.0
        var geminiReset = Date().addingTimeInterval(17940)
        var tpWeeklyPct = 100.0
        var tpReset = Date().addingTimeInterval(230400)

        for group in groups {
            let dName = (group["displayName"] as? String) ?? ""
            if let buckets = group["buckets"] as? [[String: Any]] {
                for b in buckets {
                    let window = (b["window"] as? String) ?? ""
                    let bucketId = (b["bucketId"] as? String) ?? ""
                    if window == "weekly" {
                        let remFrac = (b["remainingFraction"] as? Double) ?? 1.0
                        let pct = remFrac * 100.0
                        let resetStr = (b["resetTime"] as? String) ?? ""
                        let rDate = isoFormatter.date(from: resetStr) ?? Date().addingTimeInterval(86400 * 3)

                        if dName.contains("Gemini") || bucketId == "gemini-weekly" {
                            geminiWeeklyPct = pct
                            geminiReset = rDate
                        } else if dName.contains("Claude") || bucketId == "3p-weekly" {
                            tpWeeklyPct = pct
                            tpReset = rDate
                        }
                    }
                }
            }
        }

        // 2. Query fetchAvailableModels for individual model allocations & gemini-3.1-flash-image
        var imagePct: Double? = nil
        var imageReset: Date? = nil
        var quotaItems: [QuotaItem] = []

        if let modelsUrl = URL(string: availableModelsEndpoint) {
            var modelsReq = URLRequest(url: modelsUrl)
            modelsReq.httpMethod = "POST"
            modelsReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            modelsReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            modelsReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            modelsReq.httpBody = quotaReq.httpBody

            if let (modelsData, modelsResp) = try? await session.data(for: modelsReq),
               let httpModelsResp = modelsResp as? HTTPURLResponse, httpModelsResp.statusCode == 200,
               let modelsJson = try? JSONSerialization.jsonObject(with: modelsData) as? [String: Any],
               let modelsDict = modelsJson["models"] as? [String: [String: Any]] {

                for (modelId, mInfo) in modelsDict {
                    let dName = (mInfo["displayName"] as? String) ?? modelId
                    let qInfo = mInfo["quotaInfo"] as? [String: Any]
                    let remFrac = (qInfo?["remainingFraction"] as? Double) ?? 1.0
                    let pct = remFrac * 100.0
                    let rStr = (qInfo?["resetTime"] as? String) ?? ""
                    let rDate = isoFormatter.date(from: rStr) ?? Date().addingTimeInterval(17940)

                    let provider: AIProvider = modelId.lowercased().contains("claude") ? .claude : .gemini
                    let iconKind: QuotaIconKind = modelId.lowercased().contains("claude") ? .sunburst : .sparkle

                    quotaItems.append(QuotaItem(
                        name: dName,
                        provider: provider,
                        iconKind: iconKind,
                        remainingPercentage: pct,
                        resetDate: rDate
                    ))

                    if modelId.contains("flash-image") || modelId.contains("image") {
                        imagePct = pct
                        imageReset = rDate
                    }
                }
            }
        }

        return DirectQuotaResult(
            geminiWeeklyPercentage: geminiWeeklyPct,
            geminiResetDate: geminiReset,
            thirdPartyWeeklyPercentage: tpWeeklyPct,
            thirdPartyResetDate: tpReset,
            imageQuotaPercentage: imagePct,
            imageQuotaResetDate: imageReset,
            models: quotaItems,
            subscriptionTier: "PRO"
        )
    }
}
