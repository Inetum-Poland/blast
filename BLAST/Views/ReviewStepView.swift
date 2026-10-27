//
//  ReviewStepView.swift
//  BLAST
//

import SwiftUI

struct ReviewStepView: View {
    @Bindable var model: AppModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Review",
                message: """
                Each blueprint is created but not deployed, so you can open it in \
                Jamf Pro and check the App Settings form before anything ships.
                """
            )

            List {
                ForEach(model.plans) { plan in
                    Section {
                        ForEach(plan.grants) { grant in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(grant.composedIdentifier)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Text(
                                    BlueprintBuilder.justification(
                                        template: model.options.justificationTemplate,
                                        grant: grant,
                                        profileNames: plan.sourceProfiles
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        DisclosureGroup(
                            "Request body",
                            isExpanded: expansion(for: plan.id)
                        ) {
                            ScrollView(.horizontal) {
                                Text(model.previewJSON(for: plan))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 280)
                        }
                        .font(.callout)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name)
                                .font(.headline)
                            Text(
                                """
                                \(plan.grants.count) app\(plan.grants.count == 1 ? "" : "s") · \
                                \(model.options.delivery.componentIdentifier)
                                """
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOn in
                if isOn { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

struct SummaryStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Done", message: message)

            List {
                ForEach(model.outcomes) { outcome in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(
                            systemName: outcome.succeeded
                                ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                        .foregroundStyle(outcome.succeeded ? .green : .red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.name)
                                .font(.headline)
                            if let failure = outcome.failure {
                                Text(failure)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(
                                    "\(outcome.appCount) app\(outcome.appCount == 1 ? "" : "s")"
                                    + (outcome.blueprintID.map { " · \($0)" } ?? "")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)

            if model.outcomes.contains(where: \.succeeded) {
                Label(
                    """
                    Deploy each blueprint in Jamf Pro when you are ready. On macOS 27 \
                    the user still sees one consolidated consent prompt and has to \
                    choose Allow; there is no silent grant.
                    """,
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    private var message: String {
        let created = model.outcomes.filter(\.succeeded).count
        let failed = model.outcomes.count - created
        if failed == 0 {
            return "\(created) blueprint\(created == 1 ? "" : "s") created."
        }
        return "\(created) created, \(failed) failed."
    }
}
