//
//  JamfProClient.swift
//  BLAST
//

import Foundation

/// Reads configuration profiles straight from a Jamf Pro server. Blueprints are
/// not part of the Jamf Pro API, so this connection can only scan.
actor JamfProClient: ProfileSource {
    enum Failure: LocalizedError, Sendable {
        case badURL
        case authentication(Int, String)
        case forbidden
        case notFound(URL)
        case server(Int, String, URL)
        case transport(String)
        case malformedResponse(String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                "That does not look like a Jamf Pro URL."
            case .authentication(let status, let detail):
                """
                Jamf Pro rejected these credentials (HTTP \(status)).
                \(detail)
                """
            case .forbidden:
                """
                The account is not allowed to read configuration profiles.
                Grant Read on macOS Configuration Profiles to the API role or \
                the user account, then try again.
                """
            case .notFound(let url):
                "Jamf Pro has no \(url.path). Check the server URL."
            case .server(let status, let detail, let url):
                "HTTP \(status) from \(url.path): \(detail)"
            case .transport(let detail):
                "Could not reach Jamf Pro: \(detail)"
            case .malformedResponse(let detail):
                "Jamf Pro returned something unexpected: \(detail)"
            }
        }
    }

    private let credentials: JamfProCredentials
    private let baseURL: URL
    private let session: URLSession
    private var token: String?
    private var tokenExpiry: Date = .distantPast

    init(credentials: JamfProCredentials) throws {
        guard let baseURL = credentials.baseURL else { throw Failure.badURL }
        self.credentials = credentials
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "BLAST/1.0"]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Authentication

    func signIn() async throws {
        switch credentials.authKind {
        case .apiClient: try await signInWithClient()
        case .localAccount: try await signInWithAccount()
        }
    }

    /// The OAuth endpoint moved between Jamf Pro releases, so both spellings
    /// are tried.
    private func signInWithClient() async throws {
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientID.trimmed),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]
        let body = form.percentEncodedQuery?.data(using: .utf8)

        var lastFailure: Failure?
        for path in ["api/oauth/token", "api/v1/oauth/token"] {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue(
                "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await send(request)
            if (200..<300).contains(response.statusCode) {
                struct TokenResponse: Decodable {
                    let access_token: String
                    let expires_in: Int?
                }
                guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data)
                else {
                    throw Failure.malformedResponse("no access_token in the token response")
                }
                token = decoded.access_token
                tokenExpiry = Date().addingTimeInterval(Double(decoded.expires_in ?? 1200))
                return
            }
            lastFailure = response.statusCode == 404
                ? .notFound(request.url ?? baseURL)
                : .authentication(response.statusCode, ClassicProfiles.message(in: data))
            if response.statusCode != 404 { break }
        }
        throw lastFailure ?? Failure.malformedResponse("no token endpoint answered")
    }

    private func signInWithAccount() async throws {
        let pair = "\(credentials.username.trimmed):\(credentials.password)"
        var request = URLRequest(url: baseURL.appending(path: "api/v1/auth/token"))
        request.httpMethod = "POST"
        request.setValue(
            "Basic \(Data(pair.utf8).base64EncodedString())",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.authentication(response.statusCode, ClassicProfiles.message(in: data))
        }
        struct TokenResponse: Decodable {
            let token: String
            let expires: String?
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw Failure.malformedResponse("no token in the authentication response")
        }
        token = decoded.token
        tokenExpiry = decoded.expires
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? Date().addingTimeInterval(1800)
    }

    private func validToken() async throws -> String {
        if let token, tokenExpiry.timeIntervalSinceNow > 60 { return token }
        try await signIn()
        guard let token else {
            throw Failure.malformedResponse("the token went missing after signing in")
        }
        return token
    }

    /// Jamf Pro tokens are server-side sessions, so the app gives one back
    /// rather than leaving it valid.
    func signOut() async {
        guard let token else { return }
        var request = URLRequest(url: baseURL.appending(path: "api/v1/auth/invalidate-token"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await send(request)
        self.token = nil
        tokenExpiry = .distantPast
    }

    // MARK: - Profiles

    func configurationProfiles() async throws -> [ProfileSummary] {
        let data = try await get(path: "JSSResource/osxconfigurationprofiles")
        guard let summaries = ClassicProfiles.summaries(from: data) else {
            throw Failure.malformedResponse("could not read the profile list")
        }
        return summaries
    }

    func finding(for summary: ProfileSummary) async throws -> ProfileFinding? {
        let data = try await get(path: "JSSResource/osxconfigurationprofiles/id/\(summary.id)")
        guard let result = ClassicProfiles.finding(from: data, summary: summary) else {
            throw Failure.malformedResponse("could not read profile \(summary.id)")
        }
        return result
    }

    // MARK: - Plumbing

    private func get(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw Failure.authentication(401, ClassicProfiles.message(in: data))
        case 403: throw Failure.forbidden
        case 404: throw Failure.notFound(request.url ?? baseURL)
        default:
            throw Failure.server(
                response.statusCode,
                ClassicProfiles.message(in: data),
                request.url ?? baseURL
            )
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw Failure.malformedResponse("not an HTTP response")
            }
            return (data, http)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
    }
}
