//
//  ProfilesStepView.swift
//  BLAST
//

import SwiftUI

struct ProfilesStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Profiles granting Accessibility", message: summary)

            if !model.canCreateBlueprints && !model.findings.isEmpty {
                Label {
                    Text(
                        """
                        This is a Jamf Pro connection, so the list stops here. \
                        Reconnect with a Platform API integration to turn these \
                        into blueprints.
                        """
                    )
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if model.findings.isEmpty {
                ContentUnavailableView(
                    "No PPPC Accessibility grants",
                    systemImage: "checkmark.shield",
                    description: Text(
                        """
                        None of the macOS configuration profiles in this tenant \
                        grant Accessibility through a PPPC payload.
                        """
                    )
                )
            } else {
                List {
                    ForEach(model.filteredFindings) { finding in
                        Section {
                            ForEach(finding.grants) { grant in
                                GrantRow(grant: grant)
                            }
                            if finding.payloadUnreadable {
                                Label(
                                    """
                                    This profile is signed, so Jamf Pro returns its \
                                    payload as an opaque blob. Check it by hand.
                                    """,
                                    systemImage: "lock.doc"
                                )
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                        } header: {
                            ProfileHeader(model: model, finding: finding)
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(
                    text: $model.profileSearch,
                    placement: .toolbar,
                    prompt: "Profile or bundle ID"
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Select All") {
                    model.selectedProfileIDs = Set(model.convertibleFindings.map(\.id))
                }
                .disabled(model.convertibleFindings.isEmpty)
                Button("Select None") { model.selectedProfileIDs = [] }
                    .disabled(model.selectedProfileIDs.isEmpty)
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
            }
        }
    }

    private var summary: String {
        let profiles = model.convertibleFindings.count
        let apps = model.convertibleFindings.reduce(0) { $0 + $1.convertibleGrants.count }
        guard profiles > 0 else {
            return "Nothing to convert in this tenant."
        }
        return """
        \(profiles) profile\(profiles == 1 ? "" : "s") grant Accessibility to \
        \(apps) app\(apps == 1 ? "" : "s"). Pick the ones to convert.
        """
    }
}

private struct ProfileHeader: View {
    @Bindable var model: AppModel
    let finding: ProfileFinding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(isOn: selection) {
                Text(finding.name)
                    .font(.headline)
            }
            .disabled(finding.convertibleGrants.isEmpty)

            Spacer(minLength: 8)

            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var selection: Binding<Bool> {
        Binding(
            get: { model.selectedProfileIDs.contains(finding.id) },
            set: { isOn in
                if isOn {
                    model.selectedProfileIDs.insert(finding.id)
                } else {
                    model.selectedProfileIDs.remove(finding.id)
                }
            }
        )
    }

    private var details: String {
        var parts = ["ID \(finding.id)"]
        if !finding.level.isEmpty { parts.append(finding.level) }
        parts.append(finding.scopeSummary)
        return parts.joined(separator: " · ")
    }
}

private struct GrantRow: View {
    let grant: AccessibilityGrant

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(grant.isConvertible ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(grant.identifier)
                    .font(.callout.monospaced())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !grant.isConvertible {
                Text(reasonSkipped)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        grant.isConvertible ? "app.badge.checkmark" : "exclamationmark.triangle"
    }

    private var subtitle: String {
        var parts: [String] = [grant.identifierType.isEmpty ? "unknown type" : grant.identifierType]
        if !grant.authorization.isEmpty { parts.append(grant.authorization) }
        if let team = grant.teamID { parts.append("Team \(team)") }
        if grant.codeRequirement.isEmpty { parts.append("no designated requirement") }
        return parts.joined(separator: " · ")
    }

    private var reasonSkipped: String {
        if !grant.grantsAccess { return "Does not grant access" }
        return "Path-based, no bundle ID"
    }
}
