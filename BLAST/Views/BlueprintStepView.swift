//
//  BlueprintStepView.swift
//  BLAST
//

import SwiftUI

struct BlueprintStepView: View {
    @Bindable var model: AppModel
    @State private var showsAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: "Shape of the blueprints", message: message)

            Form {
                if model.selectedFindings.count > 1 {
                    Section {
                        Picker("Layout", selection: $model.grouping) {
                            ForEach(BlueprintGrouping.allCases) { grouping in
                                Text(grouping.displayName).tag(grouping)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        Text(model.grouping.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("One blueprint or many")
                    }
                }

                Section {
                    Picker("Component", selection: $model.options.delivery) {
                        ForEach(DeclarationDelivery.allCases) { delivery in
                            Text(delivery.displayName).tag(delivery)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(model.nativeComponentAvailable == false)

                    Text(model.options.delivery.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.nativeComponentAvailable == false {
                        Label(
                            """
                            This tenant's component catalogue does not offer \
                            com.jamf.ddm-strict yet, so the declaration has to go \
                            in as raw JSON.
                            """,
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How the declaration is delivered")
                }

                Section {
                    TextField("Name prefix", text: $model.options.namePrefix)
                    TextField(
                        "Justification",
                        text: $model.options.justificationTemplate,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                } header: {
                    Text("Naming and consent text")
                } footer: {
                    Text(
                        """
                        The justification is required and is the sentence the user \
                        reads on the consent prompt. {app} becomes the bundle ID and \
                        {profile} the source profile name.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(isExpanded: $showsAdvanced) {
                    Picker("Channel", selection: $model.options.channel) {
                        Text("User").tag("USER")
                        Text("System").tag("SYSTEM")
                    }
                    TextField(
                        "Activation predicate",
                        text: $model.options.activationPredicate,
                        prompt: Text("Optional")
                    )
                    Text(
                        """
                        On macOS, privacy declarations install on the user channel \
                        and need an MDM-enabled local user, so leave the channel on \
                        User unless you know otherwise.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Advanced")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var message: String {
        let apps = model.selectedAppCount
        return """
        \(apps) app\(apps == 1 ? "" : "s") will be written into a \
        com.apple.configuration.app.settings declaration, keyed by bundle ID and \
        designated requirement.
        """
    }
}
