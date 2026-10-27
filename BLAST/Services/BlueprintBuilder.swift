//
//  BlueprintBuilder.swift
//  BLAST
//

import Foundation

/// Turns PPPC Accessibility grants into `com.apple.configuration.app.settings`
/// blueprint requests.
nonisolated enum BlueprintBuilder {
    static let declarationType = "com.apple.configuration.app.settings"

    /// Groups the selected findings into the blueprints that will be created.
    static func plans(
        for findings: [ProfileFinding],
        grouping: BlueprintGrouping,
        options: BlueprintOptions,
        existingNames: Set<String>
    ) -> [BlueprintPlan] {
        let usable = findings.filter { !$0.convertibleGrants.isEmpty }
        guard !usable.isEmpty else { return [] }

        var taken = existingNames
        var plans: [BlueprintPlan] = []

        switch grouping {
        case .combined:
            // One declaration keyed by app, so a duplicate bundle ID across two
            // profiles collapses into a single entry.
            var seen: Set<String> = []
            var grants: [AccessibilityGrant] = []
            for finding in usable {
                for grant in finding.convertibleGrants where seen.insert(grant.identifier).inserted {
                    grants.append(grant)
                }
            }
            plans.append(
                BlueprintPlan(
                    name: uniqueName("\(options.namePrefix) — App Privacy Defaults", taken: &taken),
                    sourceProfiles: usable.map(\.name),
                    grants: grants
                )
            )
        case .separate:
            for finding in usable {
                plans.append(
                    BlueprintPlan(
                        name: uniqueName("\(options.namePrefix) — \(finding.name)", taken: &taken),
                        sourceProfiles: [finding.name],
                        grants: finding.convertibleGrants
                    )
                )
            }
        }
        return plans
    }

    static func request(
        for plan: BlueprintPlan,
        deviceGroups: [String],
        options: BlueprintOptions
    ) -> CreateBlueprintRequest {
        var defaults: [String: AppSettingsPayload.PermissionDefaults] = [:]
        for grant in plan.grants {
            defaults[grant.composedIdentifier] = .init(
                organizationJustification: justification(
                    template: options.justificationTemplate,
                    grant: grant,
                    profileNames: plan.sourceProfiles
                )
            )
        }

        let declaration = CreateBlueprintRequest.Declaration(
            type: declarationType,
            channelType: options.channel,
            kind: "CONFIGURATION",
            // Only the raw component needs a payload key; the typed component
            // does not define the field.
            payloadKey: options.delivery == .custom ? 1 : nil,
            payload: AppSettingsPayload(
                privacy: .init(permissionDefaults: defaults)
            )
        )

        let predicate = options.activationPredicate.trimmed
        return CreateBlueprintRequest(
            name: plan.name,
            description: description(for: plan),
            scope: .init(deviceGroups: deviceGroups),
            steps: [
                .init(
                    name: "App privacy permission defaults",
                    components: [
                        .init(
                            identifier: options.delivery.componentIdentifier,
                            configuration: .init(declarations: [declaration])
                        )
                    ],
                    activationPredicate: predicate.isEmpty ? nil : predicate
                )
            ]
        )
    }

    static func json(
        for plan: BlueprintPlan,
        deviceGroups: [String],
        options: BlueprintOptions,
        prettyPrinted: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .withoutEscapingSlashes]
            : [.withoutEscapingSlashes]
        return try encoder.encode(
            request(for: plan, deviceGroups: deviceGroups, options: options)
        )
    }

    // MARK: - Text

    private static func description(for plan: BlueprintPlan) -> String {
        let apps = plan.grants.count
        let sources = plan.sourceProfiles.joined(separator: ", ")
        return """
        Accessibility defaults for \(apps) app\(apps == 1 ? "" : "s"), \
        converted from PPPC in: \(sources).
        """
    }

    static func justification(
        template: String,
        grant: AccessibilityGrant,
        profileNames: [String]
    ) -> String {
        let text = template
            .replacingOccurrences(of: "{app}", with: grant.identifier)
            .replacingOccurrences(
                of: "{profile}", with: profileNames.first ?? ""
            )
            .trimmed
        // The API requires a justification: it is the text the user reads on the
        // consent prompt.
        return text.isEmpty
            ? "\(grant.identifier) needs Accessibility access."
            : text
    }

    private static func uniqueName(
        _ candidate: String, taken: inout Set<String>
    ) -> String {
        var name = String(candidate.prefix(200))
        var suffix = 2
        while taken.contains(name) {
            name = String("\(candidate) (\(suffix))".prefix(200))
            suffix += 1
        }
        taken.insert(name)
        return name
    }
}
