//
//  BlueprintRequest.swift
//  BLAST
//

import Foundation

/// How the `com.apple.configuration.app.settings` declaration is wrapped in a
/// blueprint component.
nonisolated enum DeclarationDelivery: String, CaseIterable, Identifiable, Codable, Sendable {
    /// `com.jamf.ddm-strict` — the schema-validated component. Jamf Pro renders
    /// it as the typed App Settings form.
    case native
    /// `com.jamf.ddm.custom-declarations` — stored as an opaque JSON blob.
    case custom

    var id: String { rawValue }

    var componentIdentifier: String {
        switch self {
        case .native: "com.jamf.ddm-strict"
        case .custom: "com.jamf.ddm.custom-declarations"
        }
    }

    var displayName: String {
        switch self {
        case .native: "App Settings component"
        case .custom: "Custom declaration"
        }
    }

    var explanation: String {
        switch self {
        case .native:
            "Delivered through the typed, schema-validated component. Jamf Pro shows it as the App Settings form and rejects an unrecognised key."
        case .custom:
            "Delivered as raw JSON. Jamf Pro stores it without validating and silently drops any key it does not recognise."
        }
    }
}

nonisolated enum BlueprintGrouping: String, CaseIterable, Identifiable, Sendable {
    case combined, separate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .combined: "One combined blueprint"
        case .separate: "A separate blueprint per profile"
        }
    }

    var explanation: String {
        switch self {
        case .combined:
            "Every app lands in a single app.settings declaration. Recommended: Apple does not define how overlapping permission defaults from two declarations merge."
        case .separate:
            "Each profile becomes its own blueprint, so each one delivers its own app.settings declaration."
        }
    }
}

// MARK: - Request body

/// Mirrors `CreateBlueprintRequest` from the Blueprints API.
nonisolated struct CreateBlueprintRequest: Encodable, Sendable {
    var name: String
    var description: String?
    var scope: Scope
    var steps: [Step]

    struct Scope: Encodable, Sendable {
        /// The API requires at least one group, so a blueprint cannot be
        /// created unscoped. Deployment is a separate call.
        var deviceGroups: [String]
    }

    struct Step: Encodable, Sendable {
        var name: String?
        var components: [Component]
        var activationPredicate: String?
    }

    struct Component: Encodable, Sendable {
        var identifier: String
        var configuration: Configuration
    }

    struct Configuration: Encodable, Sendable {
        var declarations: [Declaration]
    }

    struct Declaration: Encodable, Sendable {
        var type: String
        var channelType: String
        var kind: String
        /// Only the custom-declarations component requires a payload key; the
        /// typed component does not define the field.
        var payloadKey: Int?
        var payload: AppSettingsPayload

        enum CodingKeys: String, CodingKey {
            case type, channelType, kind, payloadKey, payload
        }
    }
}

nonisolated struct AppSettingsPayload: Encodable, Sendable {
    var privacy: Privacy

    enum CodingKeys: String, CodingKey {
        case privacy = "Privacy"
    }

    struct Privacy: Encodable, Sendable {
        var permissionDefaults: [String: PermissionDefaults]

        enum CodingKeys: String, CodingKey {
            case permissionDefaults = "PermissionDefaults"
        }
    }

    struct PermissionDefaults: Encodable, Sendable {
        var organizationJustification: String
        var accessibility: String = "Allow"

        enum CodingKeys: String, CodingKey {
            case organizationJustification = "OrganizationJustification"
            case accessibility = "Accessibility"
        }
    }
}

// MARK: - Plans

nonisolated struct BlueprintPlan: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var sourceProfiles: [String]
    var grants: [AccessibilityGrant]
}

nonisolated struct BlueprintOptions: Sendable {
    var delivery: DeclarationDelivery = .native
    var channel: String = "USER"
    var namePrefix: String = "Accessibility"
    var justificationTemplate: String = Self.defaultJustification
    var activationPredicate: String = ""

    static let defaultJustification =
        "{app} needs Accessibility access to work on your managed Mac."
}
