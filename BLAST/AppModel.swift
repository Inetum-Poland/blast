//
//  AppModel.swift
//  BLAST
//

import Foundation
import Observation

enum FlowStep: Int, CaseIterable, Identifiable, Hashable {
    case connection, profiles, blueprint, scope, review, summary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .profiles: "Profiles"
        case .blueprint: "Blueprints"
        case .scope: "Scope"
        case .review: "Review"
        case .summary: "Summary"
        }
    }

    var symbol: String {
        switch self {
        case .connection: "key.horizontal"
        case .profiles: "doc.text.magnifyingglass"
        case .blueprint: "square.stack.3d.up"
        case .scope: "person.2"
        case .review: "checklist"
        case .summary: "checkmark.seal"
        }
    }
}

nonisolated struct CreationOutcome: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let appCount: Int
    let blueprintID: String?
    let failure: String?

    var succeeded: Bool { failure == nil }
}

@MainActor
@Observable
final class AppModel {
    // Flow
    var step: FlowStep = .connection
    var alert: String?

    // Connection
    var settings = CredentialStore.load()
    var rememberCredentials = true
    var isConnecting = false
    var connectedSummary: String?
    /// Reads profiles: either the gateway or a direct Jamf Pro connection.
    private var source: (any ProfileSource)?
    /// Set only for a Platform API connection, which is the one that can write.
    private var platformClient: PlatformClient?

    /// Whether the gateway offers the typed App Settings component. `nil` means
    /// the catalogue could not be read.
    var nativeComponentAvailable: Bool?

    // Scan
    var isScanning = false
    var scanned = 0
    var scanTotal = 0
    var findings: [ProfileFinding] = []
    var selectedProfileIDs: Set<Int> = []
    var profileSearch = ""

    // Blueprint shape
    var grouping: BlueprintGrouping = .combined
    var options = BlueprintOptions()

    // Scope
    var isLoadingGroups = false
    var deviceGroups: [DeviceGroup] = []
    var groupSearch = ""
    var selectedGroupIDs: Set<String> = []
    var groupLoadFailure: String?

    // Result
    var isCreating = false
    var outcomes: [CreationOutcome] = []

    // MARK: - Derived

    var isConnected: Bool { source != nil }

    /// Blueprints are a Platform API capability, so a Jamf Pro connection can
    /// only scan.
    var canCreateBlueprints: Bool { platformClient != nil }

    var convertibleFindings: [ProfileFinding] {
        findings.filter { !$0.convertibleGrants.isEmpty }
    }

    var filteredFindings: [ProfileFinding] {
        let query = profileSearch.trimmed
        guard !query.isEmpty else { return findings }
        return findings.filter { finding in
            finding.name.localizedCaseInsensitiveContains(query)
                || finding.grants.contains {
                    $0.identifier.localizedCaseInsensitiveContains(query)
                }
        }
    }

    var selectedFindings: [ProfileFinding] {
        findings.filter { selectedProfileIDs.contains($0.id) }
    }

    var selectedAppCount: Int {
        selectedFindings.reduce(0) { $0 + $1.convertibleGrants.count }
    }

    var filteredGroups: [DeviceGroup] {
        let query = groupSearch.trimmed
        guard !query.isEmpty else { return deviceGroups }
        return deviceGroups.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var plans: [BlueprintPlan] {
        BlueprintBuilder.plans(
            for: selectedFindings,
            grouping: grouping,
            options: options,
            existingNames: existingBlueprintNames
        )
    }

    private var existingBlueprintNames: Set<String> = []

    var canContinue: Bool {
        switch step {
        case .connection: isConnected && !convertibleFindings.isEmpty
        case .profiles: selectedAppCount > 0 && canCreateBlueprints
        case .blueprint: true
        case .scope: !selectedGroupIDs.isEmpty
        case .review: !isCreating
        case .summary: false
        }
    }

    // MARK: - Connection

    func connect() async {
        guard settings.isComplete else {
            alert = "Fill in the remaining connection details first."
            return
        }
        isConnecting = true
        defer { isConnecting = false }

        source = nil
        platformClient = nil
        connectedSummary = nil
        nativeComponentAvailable = nil

        do {
            switch settings.method {
            case .platformAPI:
                let client = PlatformClient(credentials: settings.platform)
                try await client.signIn()
                platformClient = client
                source = client
                connectedSummary = """
                \(settings.platform.region.displayName) · \
                \(settings.platform.scopeKind.displayName)
                """
            case .jamfPro:
                let client = try JamfProClient(credentials: settings.pro)
                try await client.signIn()
                source = client
                connectedSummary = """
                \(settings.pro.baseURL?.host() ?? "Jamf Pro") · \
                \(settings.pro.authKind.displayName)
                """
            }
        } catch {
            connectedSummary = nil
            alert = error.localizedDescription
            return
        }

        if rememberCredentials { CredentialStore.save(settings) }
        await detectNativeComponent()
        await scan()
    }

    func signOut() {
        if let pro = source as? JamfProClient {
            Task { await pro.signOut() }
        }
        source = nil
        platformClient = nil
        connectedSummary = nil
        findings = []
        selectedProfileIDs = []
        deviceGroups = []
        selectedGroupIDs = []
        outcomes = []
        nativeComponentAvailable = nil
        step = .connection
    }

    func forgetCredentials() {
        CredentialStore.forget(settings)
        let method = settings.method
        settings = ConnectionSettings()
        settings.method = method
        signOut()
    }

    /// The typed component only appears once the tenant is on a Jamf Pro
    /// release that offers it, so the catalogue decides which one to send.
    private func detectNativeComponent() async {
        guard let client = platformClient,
              settings.platform.scopeKind.reachesBlueprints
        else {
            nativeComponentAvailable = nil
            return
        }
        do {
            let components = try await client.blueprintComponents()
            let identifiers = Set(components.map(\.identifier))
            let available = identifiers.contains(DeclarationDelivery.native.componentIdentifier)
            nativeComponentAvailable = available
            options.delivery = available ? .native : .custom
            existingBlueprintNames = (try? await client.existingBlueprintNames()) ?? []
        } catch {
            nativeComponentAvailable = nil
        }
    }

    // MARK: - Scan

    func scan() async {
        guard let source else { return }
        isScanning = true
        findings = []
        selectedProfileIDs = []
        scanned = 0
        scanTotal = 0
        defer { isScanning = false }

        let summaries: [ProfileSummary]
        do {
            summaries = try await source.configurationProfiles()
        } catch {
            alert = error.localizedDescription
            return
        }
        scanTotal = summaries.count

        var collected: [ProfileFinding] = []
        // Read in small batches: a tenant can hold hundreds of profiles and the
        // gateway is happier without hundreds of simultaneous requests.
        for batch in summaries.chunked(into: 8) {
            let results = await withTaskGroup(
                of: ProfileFinding?.self, returning: [ProfileFinding].self
            ) { group in
                for summary in batch {
                    group.addTask { try? await source.finding(for: summary) }
                }
                var found: [ProfileFinding] = []
                for await result in group {
                    if let result { found.append(result) }
                }
                return found
            }
            collected.append(contentsOf: results)
            scanned += batch.count
        }

        findings = collected.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        selectedProfileIDs = Set(convertibleFindings.map(\.id))
        if !convertibleFindings.isEmpty { step = .profiles }
    }

    // MARK: - Device groups

    func loadDeviceGroups() async {
        guard let client = platformClient, deviceGroups.isEmpty, !isLoadingGroups else { return }
        isLoadingGroups = true
        groupLoadFailure = nil
        defer { isLoadingGroups = false }
        do {
            deviceGroups = try await client.deviceGroups()
            if deviceGroups.isEmpty {
                groupLoadFailure = """
                This environment has no computer device groups yet. \
                Create one in Jamf Pro, then come back.
                """
            }
        } catch {
            groupLoadFailure = error.localizedDescription
        }
    }

    // MARK: - Create

    func createBlueprints() async {
        guard let client = platformClient else { return }
        isCreating = true
        outcomes = []
        defer { isCreating = false }

        let groups = Array(selectedGroupIDs)
        for plan in plans {
            do {
                let body = try BlueprintBuilder.json(
                    for: plan,
                    deviceGroups: groups,
                    options: options,
                    prettyPrinted: false
                )
                let id = try await client.createBlueprint(body)
                outcomes.append(
                    CreationOutcome(
                        name: plan.name,
                        appCount: plan.grants.count,
                        blueprintID: id.isEmpty ? nil : id,
                        failure: nil
                    )
                )
            } catch {
                outcomes.append(
                    CreationOutcome(
                        name: plan.name,
                        appCount: plan.grants.count,
                        blueprintID: nil,
                        failure: error.localizedDescription
                    )
                )
            }
        }
        existingBlueprintNames.formUnion(outcomes.filter(\.succeeded).map(\.name))
        step = .summary
    }

    func previewJSON(for plan: BlueprintPlan) -> String {
        let data = try? BlueprintBuilder.json(
            for: plan,
            deviceGroups: Array(selectedGroupIDs),
            options: options,
            prettyPrinted: true
        )
        guard let data else { return "Could not render this request." }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Navigation

    func advance() {
        switch step {
        case .connection: step = .profiles
        case .profiles: step = .blueprint
        case .blueprint: step = .scope
        case .scope: step = .review
        case .review, .summary: break
        }
    }

    func goBack() {
        guard let previous = FlowStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func restart() {
        selectedGroupIDs = []
        outcomes = []
        step = .profiles
    }
}

nonisolated extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
