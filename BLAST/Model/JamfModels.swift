//
//  JamfModels.swift
//  BLAST
//

import Foundation

/// The Platform API gateway is published per region. The host carries no path:
/// every namespace is served at the root since the GA release.
nonisolated enum JamfRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case us, eu, apac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .us: "United States"
        case .eu: "Europe"
        case .apac: "Asia Pacific"
        }
    }

    var host: URL {
        URL(string: "https://\(rawValue).api.jamfcloud.com")!
    }
}

/// A Platform API integration is registered against one scope and addresses it
/// with a header. Blueprints are published at environment scope only.
nonisolated enum JamfScopeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case environment, tenant

    var id: String { rawValue }

    var headerField: String {
        switch self {
        case .environment: "X-Environment-Id"
        case .tenant: "X-Tenant-Id"
        }
    }

    var displayName: String {
        switch self {
        case .environment: "Platform environment"
        case .tenant: "Jamf Pro tenant"
        }
    }

    var fieldPrompt: String {
        switch self {
        case .environment: "Platform environment ID"
        case .tenant: "Jamf Pro tenant ID"
        }
    }

    var reachesBlueprints: Bool { self == .environment }
}

nonisolated struct PlatformCredentials: Sendable, Equatable {
    var region: JamfRegion = .us
    var scopeKind: JamfScopeKind = .environment
    var scopeID: String = ""
    var clientID: String = ""
    var clientSecret: String = ""

    var isComplete: Bool {
        !scopeID.trimmed.isEmpty && !clientID.trimmed.isEmpty && !clientSecret.isEmpty
    }
}

// MARK: - Jamf Pro configuration profiles

nonisolated struct ProfileSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

/// One `Services.Accessibility` entry of a PPPC payload.
nonisolated struct AccessibilityGrant: Identifiable, Hashable, Sendable {
    var id: String { "\(profileID)-\(identifier)" }

    let profileID: Int
    let identifier: String
    let identifierType: String
    let codeRequirement: String
    let authorization: String
    let teamID: String?
    let grantsAccess: Bool

    /// macOS keys `PermissionDefaults` by the bundle ID followed by the app's
    /// designated requirement in braces. A PPPC entry already carries that
    /// requirement, so the two map onto each other directly.
    var composedIdentifier: String {
        guard !codeRequirement.isEmpty else { return identifier }
        return "\(identifier) {\(codeRequirement)}"
    }

    var isBundleIdentifier: Bool {
        let kind = identifierType.lowercased()
        return kind == "bundleid" || kind == "bundleidentifier"
    }

    /// A path-identified entry has no bundle ID, so it cannot be keyed in
    /// `PermissionDefaults`.
    var isConvertible: Bool { grantsAccess && isBundleIdentifier }
}

nonisolated struct ProfileFinding: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let level: String
    let scopeSummary: String
    let category: String
    let site: String
    let grants: [AccessibilityGrant]
    /// Jamf Pro returns a signed profile as an opaque blob, so its payload
    /// cannot be read back through the API.
    let payloadUnreadable: Bool

    var convertibleGrants: [AccessibilityGrant] {
        grants.filter(\.isConvertible)
    }
}

// MARK: - Platform inventory

nonisolated struct DeviceGroup: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String
    var deviceType: String?
    var groupType: String?

    var isComputerGroup: Bool {
        deviceType?.uppercased() == "COMPUTER"
    }

    var kindLabel: String {
        switch groupType?.uppercased() {
        case "SMART": "Smart"
        case "STATIC": "Static"
        default: groupType?.capitalized ?? ""
        }
    }
}

nonisolated struct BlueprintComponent: Identifiable, Hashable, Sendable, Decodable {
    var id: String { identifier }
    let identifier: String
    let name: String
    var description: String?
}

nonisolated struct BlueprintSummary: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String
}

// MARK: - Helpers

nonisolated extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
