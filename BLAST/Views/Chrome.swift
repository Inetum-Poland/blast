//
//  Chrome.swift
//  BLAST
//

import SwiftUI

/// Title block that opens every step.
struct StepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

/// The progress list in the sidebar. Finished steps stay reachable so a choice
/// can be revised; steps ahead of the flow do not.
struct StepSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: selection) {
            Section("Steps") {
                ForEach(FlowStep.allCases) { step in
                    Label {
                        Text(step.title)
                    } icon: {
                        Image(systemName: icon(for: step))
                    }
                    .tag(step)
                    .foregroundStyle(isReachable(step) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if let summary = model.connectedSummary {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
                Branding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private var selection: Binding<FlowStep?> {
        Binding(
            get: { model.step },
            set: { candidate in
                guard let candidate, isReachable(candidate) else { return }
                model.step = candidate
            }
        )
    }

    private func icon(for step: FlowStep) -> String {
        step.rawValue < model.step.rawValue ? "checkmark.circle.fill" : step.symbol
    }

    /// A step is reachable once the flow has passed it, and never when the
    /// connection cannot write blueprints.
    private func isReachable(_ step: FlowStep) -> Bool {
        if step.rawValue > FlowStep.profiles.rawValue, !model.canCreateBlueprints {
            return false
        }
        return step.rawValue <= model.step.rawValue
    }
}

/// Back and primary action, pinned to the bottom of the detail pane.
struct FlowBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let hint { 
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.step != .connection && model.step != .summary {
                Button("Back") { model.goBack() }
                    .keyboardShortcut(.cancelAction)
            }
            Button(primaryTitle) {
                Task { await runPrimaryAction() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!primaryEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var hint: String? {
        switch model.step {
        case .profiles:
            guard model.canCreateBlueprints else {
                return """
                Scan only: connect with a Platform API integration to create \
                blueprints.
                """
            }
            let apps = model.selectedAppCount
            return apps == 0
                ? "Select at least one profile."
                : "\(apps) app\(apps == 1 ? "" : "s") selected."
        case .scope:
            return model.selectedGroupIDs.isEmpty
                ? "The Blueprints API requires at least one device group."
                : "\(model.selectedGroupIDs.count) group(s) selected."
        case .review:
            let count = model.plans.count
            return "\(count) blueprint\(count == 1 ? "" : "s") will be created, not deployed."
        default:
            return nil
        }
    }

    private var primaryTitle: String {
        switch model.step {
        case .connection: model.isConnecting ? "Connecting…" : "Connect and Scan"
        case .profiles, .blueprint: "Continue"
        case .scope: "Review"
        case .review: model.isCreating ? "Creating…" : "Create Blueprints"
        case .summary: "Start Over"
        }
    }

    private var primaryEnabled: Bool {
        switch model.step {
        case .connection: model.settings.isComplete && !model.isConnecting
        case .profiles: model.selectedAppCount > 0 && model.canCreateBlueprints
        case .blueprint: true
        case .scope: !model.selectedGroupIDs.isEmpty
        case .review: !model.isCreating && !model.plans.isEmpty
        case .summary: true
        }
    }

    private func runPrimaryAction() async {
        switch model.step {
        case .connection: await model.connect()
        case .profiles, .blueprint: model.advance()
        case .scope: model.advance()
        case .review: await model.createBlueprints()
        case .summary: model.restart()
        }
    }
}

/// Company mark in the bottom-left of the window. The asset ships a light and a
/// dark variant, so it is drawn with its own shades rather than tinted.
private struct Branding: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(decorative: "InetumLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("Inetum Polska Sp. z o.o.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
