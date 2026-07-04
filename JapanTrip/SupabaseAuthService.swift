import Foundation

struct SupabaseSession: Codable, Equatable {
    struct User: Codable, Equatable {
        let id: UUID
        let email: String?
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

protocol SupabaseAuthenticating {
    func signIn(email: String, password: String) async throws -> SupabaseSession
    func refreshSession(refreshToken: String) async throws -> SupabaseSession
    func updatePassword(_ newPassword: String, accessToken: String) async throws
    func signOut(accessToken: String) async
}

enum SupabaseAuthError: LocalizedError {
    case invalidConfiguration
    case invalidCredentials
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "A autenticação ainda não está configurada."
        case .invalidCredentials: "E-mail ou senha incorretos."
        case .server(let message): message
        case .invalidResponse: "O servidor devolveu uma resposta inválida."
        }
    }
}

struct SupabaseAuthService: SupabaseAuthenticating {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        try await tokenRequest(
            grantType: "password",
            payload: ["email": email, "password": password]
        )
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        try await tokenRequest(
            grantType: "refresh_token",
            payload: ["refresh_token": refreshToken]
        )
    }

    func signOut(accessToken: String) async {
        var request = URLRequest(url: projectURL.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    func updatePassword(_ newPassword: String, accessToken: String) async throws {
        var request = URLRequest(url: projectURL.appending(path: "auth/v1/user"))
        request.httpMethod = "PUT"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["password": newPassword])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let error = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
            throw SupabaseAuthError.server(error?.message ?? "Não foi possível alterar a senha.")
        }
    }

    private func tokenRequest(grantType: String, payload: [String: String]) async throws -> SupabaseSession {
        var components = URLComponents(
            url: projectURL.appending(path: "auth/v1/token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components.url else { throw SupabaseAuthError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw SupabaseAuthError.invalidCredentials
            }
            let error = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
            throw SupabaseAuthError.server(error?.message ?? "Não foi possível contactar o serviço de autenticação.")
        }

        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }
}

private struct SupabaseErrorResponse: Decodable {
    let message: String?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
        case msg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .errorDescription)
            ?? container.decodeIfPresent(String.self, forKey: .msg)
    }
}
