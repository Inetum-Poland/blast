//
//  ClassicProfiles.swift
//  BLAST
//

import Foundation

/// Decoding for the Classic API's configuration profile resources. The same
/// payloads come back whether they are read through the Platform API gateway or
/// straight from a Jamf Pro server.
nonisolated enum ClassicProfiles {
    static func summaries(from data: Data) -> [ProfileSummary]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["os_x_configuration_profiles"] as? [[String: Any]]
        else { return nil }
        return list.compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            return ProfileSummary(id: id, name: item["name"] as? String ?? "Profile \(id)")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Returns `.some(nil)` for a profile that carries no Accessibility grant,
    /// and `nil` when the response could not be read at all.
    static func finding(from data: Data, summary: ProfileSummary) -> ProfileFinding?? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["os_x_configuration_profile"] as? [String: Any]
        else { return nil }

        let general = profile["general"] as? [String: Any] ?? [:]
        let payload = general["payloads"] as? String ?? ""
        let grants = PPPCParser.accessibilityGrants(inPayload: payload, profileID: summary.id)

        // A readable payload with no Accessibility entry is not interesting; a
        // signed one is reported so it can be checked by hand.
        if let grants, grants.isEmpty { return .some(nil) }
        if grants == nil, !mentionsAccessibility(payload) { return .some(nil) }

        return ProfileFinding(
            id: summary.id,
            name: general["name"] as? String ?? summary.name,
            level: general["level"] as? String ?? "",
            scopeSummary: scopeSummary(profile["scope"] as? [String: Any] ?? [:]),
            category: nestedName(general["category"]),
            site: nestedName(general["site"]),
            grants: grants ?? [],
            payloadUnreadable: grants == nil
        )
    }

    /// A signed payload is opaque, so a plain-text hint is the only clue that it
    /// is worth flagging for a manual look.
    private static func mentionsAccessibility(_ payload: String) -> Bool {
        !payload.isEmpty
            && (payload.contains(PPPCParser.payloadType) || payload.contains("Accessibility"))
    }

    private static func nestedName(_ value: Any?) -> String {
        (value as? [String: Any])?["name"] as? String ?? ""
    }

    private static func scopeSummary(_ scope: [String: Any]) -> String {
        if scope["all_computers"] as? Bool == true { return "All computers" }
        var parts: [String] = []
        let counted: [(String, String)] = [
            ("computers", "computer"),
            ("computer_groups", "group"),
            ("buildings", "building"),
            ("departments", "department")
        ]
        for (key, noun) in counted {
            let count = (scope[key] as? [Any])?.count ?? 0
            if count > 0 {
                parts.append("\(count) \(noun)\(count == 1 ? "" : "s")")
            }
        }
        return parts.isEmpty ? "Not scoped" : parts.joined(separator: ", ")
    }

    /// Pulls a human-readable sentence out of an error body, whatever shape it
    /// arrives in.
    static func message(in data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error_description", "error", "detail", "title"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
            if let errors = object["errors"] as? [[String: Any]],
               let text = errors.first?["description"] as? String {
                return text
            }
        }
        let text = String(decoding: data, as: UTF8.self).trimmed
        return text.isEmpty ? "no detail returned" : String(text.prefix(300))
    }
}
