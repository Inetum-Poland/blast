//
//  PlatformClient.swift
//  BLAST
//

import Foundation

/// Talks to the Jamf Platform API gateway. Every namespace is served at the
/// root of the regional host, and the integration's scope travels in a header.
actor PlatformClient: ProfileSource {
    enum Capability: String, Sendable {
        case configurationProfiles = "configuration-profiles:read"
        case deviceGroups = "device-groups:read"
        case blueprintsRead = "blueprints:read"
        case blueprintsCreate = "blueprints:create"

        var permissionPath: String {
            switch self {
            case .configurationProfiles:
                "Jamf Pro → Configuration profiles → Read"
            case .deviceGroups:
                "Inventory → Device groups → Read"
            case .blueprintsRead:
                "Deployment → Blueprints → Read"
            case .blueprintsCreate:
                "Deployment → Blueprints → Create"
            }
        }
    }

    enum Failure: LocalizedError, Sendable {
        case notConnected
        case transport(String)
        case authentication(Int, String)
        case forbidden(Capability)
        case notFound(URL)
        case server(Int, String, URL)
        case malformedResponse(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                "Not signed in to the Platform API yet."
            case .transport(let detail):
                "Could not reach the Platform API: \(detail)"
            case .authentication(let status, let detail):
                """
                The Platform API rejected these credentials (HTTP \(status)).
                \(detail)
                Platform API credentials are created in Jamf Account under \
                Integrations, and are separate from a Jamf Pro API client.
                """
            case .forbidden(let capability):
                """
                The integration is missing the \(capability.rawValue) permission.
                Each capability is a separate tick box in Jamf Account: \
                \(capability.permissionPath).
                """
            case .notFound(let url):
                """
                The gateway does not serve \(url.path).
                Check that the region matches the one your tenant lives in.
                """
            case .server(let status, let detail, let url):
                "HTTP \(status) from \(url.path): \(detail)"
            case .malformedResponse(let detail):
                "The Platform API returned something unexpected: \(detail)"
            }
        }
    }

    private let credentials: PlatformCredentials
    private let session: URLSession
    private var token: String?
    private var tokenExpiry: Date = .distantPast

    init(credentials: PlatformCredentials) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "BLAST/1.0"
        ]
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Authentication

    /// Exchanges the client credentials for a bearer token.
    func signIn() async throws {
        let url = credentials.region.host.appending(path: "auth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientID.trimmed),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.authentication(response.statusCode, message(in: data))
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int?
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw Failure.malformedResponse("no access_token in the token response")
        }
        token = decoded.access_token
        tokenExpiry = Date().addingTimeInterval(Double(decoded.expires_in ?? 3600))
    }

    private func validToken() async throws -> String {
        if let token, tokenExpiry.timeIntervalSinceNow > 60 { return token }
        try await signIn()
        guard let token else { throw Failure.notConnected }
        return token
    }

    // MARK: - Configuration profiles (Jamf Pro Classic, through the gateway)

    func configurationProfiles() async throws -> [ProfileSummary] {
        let data = try await get(
            path: "proclassic/osxconfigurationprofiles",
            capability: .configurationProfiles
        )
        guard let summaries = ClassicProfiles.summaries(from: data) else {
            throw Failure.malformedResponse("could not read the profile list")
        }
        return summaries
    }

    /// Reads one profile and extracts its Accessibility grants, or `nil` when
    /// the profile has no PPPC Accessibility entry at all.
    func finding(for summary: ProfileSummary) async throws -> ProfileFinding? {
        let data = try await get(
            path: "proclassic/osxconfigurationprofiles/id/\(summary.id)",
            capability: .configurationProfiles
        )
        guard let result = ClassicProfiles.finding(from: data, summary: summary) else {
            throw Failure.malformedResponse("could not read profile \(summary.id)")
        }
        return result
    }

    // MARK: - Platform inventory

    func deviceGroups() async throws -> [DeviceGroup] {
        struct Page: Decodable { let results: [DeviceGroup] }
        // The filter is RSQL. Some gateways reject it, so fall back to the
        // unfiltered list and sort computers out locally.
        let filtered = "device-groups/v1/device-groups?page-size=200"
            + "&filter=deviceType%3D%3D%22COMPUTER%22"
        let data: Data
        do {
            data = try await get(path: filtered, capability: .deviceGroups)
        } catch Failure.server(let status, _, _) where status == 400 {
            data = try await get(
                path: "device-groups/v1/device-groups?page-size=200",
                capability: .deviceGroups
            )
        }
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw Failure.malformedResponse("could not read the device group list")
        }
        return page.results
            .filter { $0.deviceType == nil || $0.isComputerGroup }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Blueprints

    func blueprintComponents() async throws -> [BlueprintComponent] {
        struct Page: Decodable { let results: [BlueprintComponent] }
        let data = try await get(
            path: "blueprints/v1/blueprint-components?page-size=200",
            capability: .blueprintsRead
        )
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw Failure.malformedResponse("could not read the component catalogue")
        }
        return page.results
    }

    func existingBlueprintNames() async throws -> Set<String> {
        struct Page: Decodable { let results: [BlueprintSummary] }
        let data = try await get(
            path: "blueprints/v1/blueprints?page=0&page-size=200",
            capability: .blueprintsRead
        )
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw Failure.malformedResponse("could not read the blueprint list")
        }
        return Set(page.results.map(\.name))
    }

    /// Returns the new blueprint's identifier.
    func createBlueprint(_ body: Data) async throws -> String {
        let url = credentials.region.host.appending(path: "blueprints/v1/blueprints")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await perform(request, capability: .blueprintsCreate)
        struct Created: Decodable { let id: String? }
        return (try? JSONDecoder().decode(Created.self, from: data))?.id ?? ""
    }

    // MARK: - Plumbing

    private func get(path: String, capability: Capability) async throws -> Data {
        let url = credentials.region.host.appending(path: path)
        var request = URLRequest(url: resolved(url, rawPath: path))
        request.httpMethod = "GET"
        return try await perform(request, capability: capability)
    }

    /// `appending(path:)` percent-encodes a query string, so a path that
    /// already carries one is rebuilt by hand.
    private func resolved(_ url: URL, rawPath: String) -> URL {
        guard rawPath.contains("?") else { return url }
        return URL(string: credentials.region.host.absoluteString + "/" + rawPath) ?? url
    }

    private func perform(_ request: URLRequest, capability: Capability) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            credentials.scopeID.trimmed,
            forHTTPHeaderField: credentials.scopeKind.headerField
        )

        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw Failure.authentication(401, message(in: data))
        case 403:
            throw Failure.forbidden(capability)
        case 404:
            throw Failure.notFound(request.url ?? credentials.region.host)
        default:
            throw Failure.server(
                response.statusCode, message(in: data), request.url ?? credentials.region.host
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

    private func message(in data: Data) -> String {
        ClassicProfiles.message(in: data)
    }
}
