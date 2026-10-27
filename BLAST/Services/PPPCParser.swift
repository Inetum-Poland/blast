//
//  PPPCParser.swift
//  BLAST
//

import Foundation

/// Reads the `Services.Accessibility` entries out of a Jamf Pro configuration
/// profile payload.
nonisolated enum PPPCParser {
    static let payloadType = "com.apple.TCC.configuration-profile-policy"
    static let service = "Accessibility"

    /// Pulls the Accessibility entries out of a profile's `general.payloads`
    /// string. Returns `nil` when the payload is not a readable plist, which is
    /// how a signed profile comes back from the API.
    static func accessibilityGrants(
        inPayload payload: String,
        profileID: Int
    ) -> [AccessibilityGrant]? {
        guard let data = payload.data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        let contents = root["PayloadContent"] as? [[String: Any]] ?? []
        var grants: [AccessibilityGrant] = []

        for payloadDict in contents
        where payloadDict["PayloadType"] as? String == payloadType {
            let services = payloadDict["Services"] as? [String: Any] ?? [:]
            let entries = services[service] as? [[String: Any]] ?? []
            for entry in entries {
                guard let identifier = entry["Identifier"] as? String,
                      !identifier.isEmpty
                else { continue }
                let requirement = entry["CodeRequirement"] as? String ?? ""
                grants.append(
                    AccessibilityGrant(
                        profileID: profileID,
                        identifier: identifier,
                        identifierType: entry["IdentifierType"] as? String ?? "",
                        codeRequirement: requirement,
                        authorization: authorization(of: entry),
                        teamID: teamID(inRequirement: requirement),
                        grantsAccess: grantsAccess(entry)
                    )
                )
            }
        }
        return grants
    }

    /// `Authorization` superseded the pre-macOS 11 `Allowed` boolean; profiles
    /// in the wild still carry either one.
    private static func authorization(of entry: [String: Any]) -> String {
        if let value = entry["Authorization"] as? String, !value.isEmpty {
            return value
        }
        if let allowed = entry["Allowed"] as? Bool {
            return allowed ? "Allow" : "Deny"
        }
        if let allowed = entry["Allowed"] as? NSNumber {
            return allowed.boolValue ? "Allow" : "Deny"
        }
        return ""
    }

    private static func grantsAccess(_ entry: [String: Any]) -> Bool {
        switch authorization(of: entry) {
        case "Allow", "AllowStandardUserToSetSystemService": true
        default: false
        }
    }

    /// The team identifier sits in the `subject.OU` field of the designated
    /// requirement. It is shown for recognition only; the composed identifier
    /// uses the whole requirement.
    static func teamID(inRequirement requirement: String) -> String? {
        let pattern = #"subject\.OU[\s\]]*\]?\s*=\s*"?([A-Za-z0-9]{10})"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: requirement,
                  range: NSRange(requirement.startIndex..., in: requirement)
              ),
              let range = Range(match.range(at: 1), in: requirement)
        else { return nil }
        return String(requirement[range]).uppercased()
    }
}
