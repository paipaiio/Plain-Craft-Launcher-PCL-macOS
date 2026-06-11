import Foundation

enum MicrosoftMinecraftLoginError: LocalizedError, Sendable {
    case missingClientID
    case httpStatus(Int, String)
    case authorizationDeclined
    case authorizationExpired
    case authorizationPending
    case slowDown
    case missingEntitlement
    case missingProfile
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "请先配置 Microsoft OAuth Client ID"
        case .httpStatus(let status, let body):
            "登录接口返回 HTTP \(status)：\(body)"
        case .authorizationDeclined:
            "你取消了 Microsoft 授权"
        case .authorizationExpired:
            "登录验证码已过期，请重新登录"
        case .authorizationPending:
            "等待你在浏览器中完成 Microsoft 授权"
        case .slowDown:
            "Microsoft 要求降低轮询频率"
        case .missingEntitlement:
            "该 Microsoft 账户未拥有 Minecraft Java 版或 Game Pass 已到期"
        case .missingProfile:
            "该 Microsoft 账户尚未创建 Minecraft 玩家档案"
        case .invalidResponse(let name):
            "登录接口响应无效：\(name)"
        }
    }
}

struct MicrosoftDeviceCode: Decodable, Equatable, Sendable {
    let userCode: String
    let deviceCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

struct MicrosoftOAuthTokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct MicrosoftMinecraftLoginResult: Equatable, Sendable {
    let profile: LauncherAccountProfile
    let secret: LauncherAccountSecret
    let minecraftProfileJSON: String
}

struct MicrosoftMinecraftLoginService: Sendable {
    typealias HTTPClient = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    let clientID: String
    var httpClient: HTTPClient

    init(
        clientID: String,
        httpClient: @escaping HTTPClient = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MicrosoftMinecraftLoginError.invalidResponse("HTTPURLResponse")
            }
            return (data, http)
        }
    ) {
        self.clientID = clientID.trimmed
        self.httpClient = httpClient
    }

    func requestDeviceCode() async throws -> MicrosoftDeviceCode {
        guard !clientID.isEmpty else { throw MicrosoftMinecraftLoginError.missingClientID }
        var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "tenant": "/consumers",
            "scope": "XboxLive.signin offline_access"
        ])
        return try await send(request, response: MicrosoftDeviceCode.self)
    }

    func pollDeviceCode(_ code: MicrosoftDeviceCode) async throws -> MicrosoftOAuthTokenResponse {
        guard !clientID.isEmpty else { throw MicrosoftMinecraftLoginError.missingClientID }
        var interval = max(code.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(max(code.expiresIn, interval)))

        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            do {
                var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = formBody([
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": clientID,
                    "device_code": code.deviceCode,
                    "scope": "XboxLive.signin offline_access"
                ])
                return try await send(request, response: MicrosoftOAuthTokenResponse.self)
            } catch MicrosoftMinecraftLoginError.authorizationPending {
                continue
            } catch MicrosoftMinecraftLoginError.slowDown {
                interval += 5
                continue
            }
        }

        throw MicrosoftMinecraftLoginError.authorizationExpired
    }

    func refreshOAuthToken(_ refreshToken: String) async throws -> MicrosoftOAuthTokenResponse {
        guard !clientID.isEmpty else { throw MicrosoftMinecraftLoginError.missingClientID }
        var request = URLRequest(url: URL(string: "https://login.live.com/oauth20_token.srf")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = formBody([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "scope": "XboxLive.signin offline_access"
        ])
        return try await send(request, response: MicrosoftOAuthTokenResponse.self)
    }

    func completeMinecraftLogin(oauth: MicrosoftOAuthTokenResponse) async throws -> MicrosoftMinecraftLoginResult {
        let xblToken = try await authenticateXboxLive(oauthAccessToken: oauth.accessToken)
        let xsts = try await authorizeXSTS(xblToken: xblToken)
        let minecraft = try await loginWithXbox(xsts: xsts)
        try await verifyEntitlements(accessToken: minecraft.accessToken)
        let profile = try await fetchProfile(accessToken: minecraft.accessToken)

        let now = Date()
        let account = LauncherAccountProfile(
            id: "microsoft:\(profile.id)",
            kind: .microsoft,
            displayName: profile.name,
            playerUUID: profile.id,
            serverURL: nil,
            createdAt: now,
            lastUsedAt: now
        )
        let expiresAt = Date().addingTimeInterval(TimeInterval(max(minecraft.expiresIn - 1200, 60)))
        let secret = LauncherAccountSecret(
            accessToken: minecraft.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiresAt
        )
        return MicrosoftMinecraftLoginResult(
            profile: account,
            secret: secret,
            minecraftProfileJSON: profile.rawJSON
        )
    }

    func loginWithDeviceCode(_ code: MicrosoftDeviceCode) async throws -> MicrosoftMinecraftLoginResult {
        try await completeMinecraftLogin(oauth: pollDeviceCode(code))
    }

    func loginWithRefreshToken(_ refreshToken: String) async throws -> MicrosoftMinecraftLoginResult {
        try await completeMinecraftLogin(oauth: refreshOAuthToken(refreshToken))
    }

    private func authenticateXboxLive(oauthAccessToken: String) async throws -> String {
        let payload = XboxAuthenticateRequest(
            properties: .init(
                authMethod: "RPS",
                siteName: "user.auth.xboxlive.com",
                rpsTicket: oauthAccessToken.hasPrefix("d=") ? oauthAccessToken : "d=\(oauthAccessToken)"
            ),
            relyingParty: "http://auth.xboxlive.com",
            tokenType: "JWT"
        )
        var request = URLRequest(url: URL(string: "https://user.auth.xboxlive.com/user/authenticate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request, response: XboxTokenResponse.self).token
    }

    private func authorizeXSTS(xblToken: String) async throws -> XSTSResponse {
        let payload = XSTSAuthorizeRequest(
            properties: .init(sandboxID: "RETAIL", userTokens: [xblToken]),
            relyingParty: "rp://api.minecraftservices.com/",
            tokenType: "JWT"
        )
        var request = URLRequest(url: URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request, response: XSTSResponse.self)
    }

    private func loginWithXbox(xsts: XSTSResponse) async throws -> MinecraftLoginResponse {
        guard let uhs = xsts.displayClaims.xui.first?.uhs else {
            throw MicrosoftMinecraftLoginError.invalidResponse("xsts uhs")
        }
        let payload = MinecraftXboxLoginRequest(identityToken: "XBL3.0 x=\(uhs);\(xsts.token)")
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request, response: MinecraftLoginResponse.self)
    }

    private func verifyEntitlements(accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/entitlements/mcstore")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let entitlements = try await send(request, response: MinecraftEntitlementsResponse.self)
        guard !entitlements.items.isEmpty else {
            throw MicrosoftMinecraftLoginError.missingEntitlement
        }
    }

    private func fetchProfile(accessToken: String) async throws -> MinecraftProfileResponse {
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let data = try await sendData(request)
            let payload = try JSONDecoder().decode(MinecraftProfilePayload.self, from: data)
            return MinecraftProfileResponse(
                id: payload.id,
                name: payload.name,
                rawJSON: String(data: data, encoding: .utf8) ?? "{}"
            )
        } catch MicrosoftMinecraftLoginError.httpStatus(404, _) {
            throw MicrosoftMinecraftLoginError.missingProfile
        }
    }

    private func send<T: Decodable>(_ request: URLRequest, response: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: await sendData(request))
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            try mapError(data: data, statusCode: http.statusCode)
        }
        return data
    }

    private func mapError(data: Data, statusCode: Int) throws -> Never {
        let body = String(data: data, encoding: .utf8) ?? ""
        if let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            switch error.error {
            case "authorization_pending":
                throw MicrosoftMinecraftLoginError.authorizationPending
            case "authorization_declined":
                throw MicrosoftMinecraftLoginError.authorizationDeclined
            case "expired_token":
                throw MicrosoftMinecraftLoginError.authorizationExpired
            case "slow_down":
                throw MicrosoftMinecraftLoginError.slowDown
            default:
                break
            }
        }
        throw MicrosoftMinecraftLoginError.httpStatus(statusCode, body)
    }

    private func formBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(formEscape(key))=\(formEscape(value))"
            }
            .sorted()
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
}

private struct XboxAuthenticateRequest: Encodable {
    struct Properties: Encodable {
        let authMethod: String
        let siteName: String
        let rpsTicket: String

        enum CodingKeys: String, CodingKey {
            case authMethod = "AuthMethod"
            case siteName = "SiteName"
            case rpsTicket = "RpsTicket"
        }
    }

    let properties: Properties
    let relyingParty: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case properties = "Properties"
        case relyingParty = "RelyingParty"
        case tokenType = "TokenType"
    }
}

private struct XSTSAuthorizeRequest: Encodable {
    struct Properties: Encodable {
        let sandboxID: String
        let userTokens: [String]

        enum CodingKeys: String, CodingKey {
            case sandboxID = "SandboxId"
            case userTokens = "UserTokens"
        }
    }

    let properties: Properties
    let relyingParty: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case properties = "Properties"
        case relyingParty = "RelyingParty"
        case tokenType = "TokenType"
    }
}

private struct XboxTokenResponse: Decodable {
    let token: String

    enum CodingKeys: String, CodingKey {
        case token = "Token"
    }
}

private struct XSTSResponse: Decodable {
    let token: String
    let displayClaims: DisplayClaims

    struct DisplayClaims: Decodable {
        let xui: [XUI]
    }

    struct XUI: Decodable {
        let uhs: String
    }

    enum CodingKeys: String, CodingKey {
        case token = "Token"
        case displayClaims = "DisplayClaims"
    }
}

private struct MinecraftXboxLoginRequest: Encodable {
    let identityToken: String
}

private struct MinecraftLoginResponse: Decodable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct MinecraftEntitlementsResponse: Decodable {
    struct Item: Decodable {
        let name: String?
    }

    let items: [Item]
}

private struct MinecraftProfilePayload: Decodable {
    let id: String
    let name: String
}

private struct MinecraftProfileResponse: Equatable {
    let id: String
    let name: String
    let rawJSON: String

    init(id: String, name: String, rawJSON: String) {
        self.id = id
        self.name = name
        self.rawJSON = rawJSON
    }
}
