import Foundation

enum AuthlibLoginError: LocalizedError, Sendable {
    case missingServerURL
    case missingUsername
    case missingPassword
    case noAvailableProfile
    case invalidSelectedProfile
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            "请填写 Authlib 认证服务器地址"
        case .missingUsername:
            "Authlib 账号不能为空"
        case .missingPassword:
            "Authlib 密码不能为空"
        case .noAvailableProfile:
            "该账号没有可用角色，请先在皮肤站创建角色"
        case .invalidSelectedProfile:
            "选择的 Authlib 角色无效"
        case .httpStatus(let status, let body):
            "Authlib 服务器返回 HTTP \(status)：\(body)"
        }
    }
}

struct AuthlibLoginRequest: Sendable {
    let serverURL: URL
    let username: String
    let password: String
    let preferredProfileID: String?
    let accountKind: LauncherAccountKind

    init(
        serverURL: URL,
        username: String,
        password: String,
        preferredProfileID: String? = nil,
        accountKind: LauncherAccountKind = .authlib
    ) {
        self.serverURL = serverURL
        self.username = username.trimmed
        self.password = password
        self.preferredProfileID = preferredProfileID
        self.accountKind = accountKind
    }
}

struct AuthlibLoginResult: Equatable, Sendable {
    let profile: LauncherAccountProfile
    let secret: LauncherAccountSecret
}

struct AuthlibLoginService: Sendable {
    typealias HTTPClient = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var httpClient: HTTPClient

    init(
        httpClient: @escaping HTTPClient = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthlibLoginError.httpStatus(0, "Invalid response")
            }
            return (data, http)
        }
    ) {
        self.httpClient = httpClient
    }

    func login(_ request: AuthlibLoginRequest) async throws -> AuthlibLoginResult {
        guard !request.serverURL.absoluteString.trimmed.isEmpty else { throw AuthlibLoginError.missingServerURL }
        guard !request.username.isEmpty else { throw AuthlibLoginError.missingUsername }
        guard !request.password.isEmpty else { throw AuthlibLoginError.missingPassword }

        let authenticate = try await authenticate(request)
        let selected = selectProfile(from: authenticate, preferredProfileID: request.preferredProfileID)
        guard let selected else { throw AuthlibLoginError.noAvailableProfile }

        var response = authenticate
        if authenticate.selectedProfile?.id != selected.id {
            response = try await refresh(
                serverURL: request.serverURL,
                accessToken: authenticate.accessToken,
                clientToken: authenticate.clientToken,
                selectedProfile: selected
            )
        }

        guard let profile = response.selectedProfile ?? selectedProfile(namedLike: selected, from: response.availableProfiles) else {
            throw AuthlibLoginError.invalidSelectedProfile
        }
        return result(
            profile: profile,
            serverURL: request.serverURL,
            accessToken: response.accessToken,
            clientToken: response.clientToken,
            username: request.username,
            password: request.password,
            accountKind: request.accountKind
        )
    }

    func validate(serverURL: URL, secret: LauncherAccountSecret) async throws {
        let payload = AuthlibValidatePayload(
            accessToken: secret.accessToken,
            clientToken: secret.clientToken,
            requestUser: true
        )
        var request = jsonRequest(url: endpoint(serverURL, "validate"))
        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await sendData(request)
    }

    func refresh(
        serverURL: URL,
        profile: LauncherAccountProfile,
        secret: LauncherAccountSecret
    ) async throws -> AuthlibLoginResult {
        guard let clientToken = secret.clientToken else {
            throw AuthlibLoginError.invalidSelectedProfile
        }
        let selectedProfile = AuthlibProfile(
            id: profile.playerUUID ?? profile.id,
            name: profile.displayName
        )
        let response = try await refresh(
            serverURL: serverURL,
            accessToken: secret.accessToken,
            clientToken: clientToken,
            selectedProfile: selectedProfile
        )
        guard let refreshedProfile = response.selectedProfile else { throw AuthlibLoginError.invalidSelectedProfile }
        return result(
            profile: refreshedProfile,
            serverURL: serverURL,
            accessToken: response.accessToken,
            clientToken: response.clientToken,
            username: secret.username,
            password: secret.password,
            accountKind: profile.kind
        )
    }

    private func authenticate(_ login: AuthlibLoginRequest) async throws -> AuthlibAuthResponse {
        let payload = AuthlibAuthenticatePayload(
            agent: .init(name: "Minecraft", version: 1),
            username: login.username,
            password: login.password,
            requestUser: true
        )
        var request = jsonRequest(url: endpoint(login.serverURL, "authenticate"))
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request, response: AuthlibAuthResponse.self)
    }

    private func refresh(
        serverURL: URL,
        accessToken: String,
        clientToken: String,
        selectedProfile: AuthlibProfile
    ) async throws -> AuthlibAuthResponse {
        let payload = AuthlibRefreshPayload(
            accessToken: accessToken,
            clientToken: clientToken,
            selectedProfile: selectedProfile,
            requestUser: true
        )
        var request = jsonRequest(url: endpoint(serverURL, "refresh"))
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request, response: AuthlibAuthResponse.self)
    }

    private func result(
        profile: AuthlibProfile,
        serverURL: URL,
        accessToken: String,
        clientToken: String,
        username: String?,
        password: String?,
        accountKind: LauncherAccountKind
    ) -> AuthlibLoginResult {
        let now = Date()
        let accountIDPrefix = accountKind == .nide ? "nide" : "authlib"
        let account = LauncherAccountProfile(
            id: "\(accountIDPrefix):\(serverURL.absoluteString):\(profile.id)",
            kind: accountKind == .nide ? .nide : .authlib,
            displayName: profile.name,
            playerUUID: profile.id,
            serverURL: serverURL,
            createdAt: now,
            lastUsedAt: now
        )
        let secret = LauncherAccountSecret(
            accessToken: accessToken,
            refreshToken: nil,
            clientToken: clientToken,
            username: username,
            password: password,
            expiresAt: nil
        )
        return AuthlibLoginResult(profile: account, secret: secret)
    }

    private func selectProfile(from response: AuthlibAuthResponse, preferredProfileID: String?) -> AuthlibProfile? {
        if let preferredProfileID,
           let profile = response.availableProfiles.first(where: { $0.id == preferredProfileID }) {
            return profile
        }
        return response.selectedProfile ?? response.availableProfiles.first
    }

    private func selectedProfile(namedLike profile: AuthlibProfile, from profiles: [AuthlibProfile]) -> AuthlibProfile? {
        profiles.first { $0.id == profile.id } ?? profile
    }

    private func jsonRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func endpoint(_ serverURL: URL, _ path: String) -> URL {
        URL(string: path, relativeTo: serverURL.absoluteString.hasSuffix("/") ? serverURL : serverURL.appendingPathComponent(""))!
    }

    private func send<T: Decodable>(_ request: URLRequest, response: T.Type) async throws -> T {
        try JSONDecoder().decode(T.self, from: await sendData(request))
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await httpClient(request)
        guard (200..<300).contains(http.statusCode) else {
            throw AuthlibLoginError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

struct AuthlibProfile: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

private struct AuthlibAuthResponse: Decodable {
    let accessToken: String
    let clientToken: String
    let selectedProfile: AuthlibProfile?
    let availableProfiles: [AuthlibProfile]
}

private struct AuthlibAuthenticatePayload: Encodable {
    struct Agent: Encodable {
        let name: String
        let version: Int
    }

    let agent: Agent
    let username: String
    let password: String
    let requestUser: Bool
}

private struct AuthlibRefreshPayload: Encodable {
    let accessToken: String
    let clientToken: String
    let selectedProfile: AuthlibProfile
    let requestUser: Bool
}

private struct AuthlibValidatePayload: Encodable {
    let accessToken: String
    let clientToken: String?
    let requestUser: Bool
}
