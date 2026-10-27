//
//  Connection.swift
//  BLAST
//

import Foundation

/// Where the app reads configuration profiles from. Only the Platform API can
/// also create blueprints.
nonisolated enum ConnectionMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    case platformAPI
    case jamfPro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .platformAPI: "Jamf Platform API"
        case .jamfPro: "Jamf Pro credentials"
        }
    }

    var explanation: String {
        switch self {
        case .platformAPI:
            "Scans profiles and creates the blueprints. Credentials come from Jamf Account under Integrations."
        case .jamfPro:
            "Scans profiles only, straight against a Jamf Pro server. Blueprints live in the Platform API, so they cannot be created this way."
        }
    }

    var symbol: String {
        switch self {
        case .platformAPI: "cloud"
        case .jamfPro: "building.2"
        }
    }

    var canCreateBlueprints: Bool { self == .platformAPI }
}

/// How the app authenticates against a Jamf Pro server directly.
nonisolated enum JamfProAuthKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case apiClient
    case localAccount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apiClient: "API role and client"
        case .localAccount: "Local user account"
        }
    }

    var explanation: String {
        switch self {
        case .apiClient:
            "A client ID and secret from Settings → API roles and clients. The role needs Read on macOS Configuration Profiles."
        case .localAccount:
            "A Jamf Pro user name and password. The account needs Read on macOS Configuration Profiles."
        }
    }
}

nonisolated struct JamfProCredentials: Sendable, Equatable {
    var urlString: String = ""
    var authKind: JamfProAuthKind = .apiClient
    var clientID: String = ""
    var clientSecret: String = ""
    var username: String = ""
    var password: String = ""

    /// Accepts a bare host and keeps only the scheme and host, so a pasted
    /// console URL with a path still works.
    var baseURL: URL? {
        var text = urlString.trimmed
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard var components = URLComponents(string: text), let host = components.host,
              !host.isEmpty
        else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        if components.scheme == nil { components.scheme = "https" }
        return components.url
    }

    var isComplete: Bool {
        guard baseURL != nil else { return false }
        switch authKind {
        case .apiClient: return !clientID.trimmed.isEmpty && !clientSecret.isEmpty
        case .localAccount: return !username.trimmed.isEmpty && !password.isEmpty
        }
    }
}

nonisolated struct ConnectionSettings: Sendable, Equatable {
    var method: ConnectionMethod = .platformAPI
    var platform = PlatformCredentials()
    var pro = JamfProCredentials()

    var isComplete: Bool {
        switch method {
        case .platformAPI: platform.isComplete
        case .jamfPro: pro.isComplete
        }
    }
}

/// Reads macOS configuration profiles. Implemented by both the Platform API
/// gateway and a direct Jamf Pro connection.
protocol ProfileSource: Sendable {
    func signIn() async throws
    func configurationProfiles() async throws -> [ProfileSummary]
    func finding(for summary: ProfileSummary) async throws -> ProfileFinding?
}
