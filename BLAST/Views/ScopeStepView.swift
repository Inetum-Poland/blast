//
//  ScopeStepView.swift
//  BLAST
//

import SwiftUI

struct ScopeStepView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Scope",
                message: """
                The Blueprints API requires at least one device group, so a \
                blueprint cannot be created unscoped. Nothing reaches a Mac until \
                you deploy it in Jamf Pro.
                """
            )

            content
        }
        .task { await model.loadDeviceGroups() }
        .toolbar {
            ToolbarItem {
                Button {
                    model.deviceGroups = []
                    Task { await model.loadDeviceGroups() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingGroups)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingGroups {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading device groups…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let failure = model.groupLoadFailure, model.deviceGroups.isEmpty {
            ContentUnavailableView {
                Label("No device groups", systemImage: "person.2.slash")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") {
                    model.deviceGroups = []
                    Task { await model.loadDeviceGroups() }
                }
            }
        } else {
            List {
                ForEach(model.filteredGroups) { group in
                    Toggle(isOn: selection(for: group)) {
                        HStack(spacing: 8) {
                            Text(group.name)
                            if !group.kindLabel.isEmpty {
                                Text(group.kindLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(group.id)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .searchable(
                text: $model.groupSearch,
                placement: .toolbar,
                prompt: "Search device groups"
            )
        }
    }

    private func selection(for group: DeviceGroup) -> Binding<Bool> {
        Binding(
            get: { model.selectedGroupIDs.contains(group.id) },
            set: { isOn in
                if isOn {
                    model.selectedGroupIDs.insert(group.id)
                } else {
                    model.selectedGroupIDs.remove(group.id)
                }
            }
        )
    }
}
