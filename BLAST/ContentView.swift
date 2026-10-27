//
//  ContentView.swift
//  BLAST
//

import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            StepSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail
                .frame(minWidth: 620, minHeight: 440)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FlowBar(model: model)
                }
                .navigationTitle("BLAST")
                .navigationSubtitle("Blueprint Legacy Accessibility Settings Transformer")
        }
        .alert(
            "Jamf reported a problem",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            )
        ) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.step {
        case .connection: ConnectionStepView(model: model)
        case .profiles: ProfilesStepView(model: model)
        case .blueprint: BlueprintStepView(model: model)
        case .scope: ScopeStepView(model: model)
        case .review: ReviewStepView(model: model)
        case .summary: SummaryStepView(model: model)
        }
    }
}

#Preview {
    ContentView()
}
