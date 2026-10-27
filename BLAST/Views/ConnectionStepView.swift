//
//  ConnectionStepView.swift
//  BLAST
//

import SwiftUI

struct ConnectionStepView: View {
    @Bindable var model: AppModel

    private let platformPermissions: [(String, String)] = [
        ("configuration-profiles:read", "Jamf Pro → Configuration profiles → Read"),
        ("device-groups:read", "Inventory → Device groups → Read"),
        ("blueprints:read", "Deployment → Blueprints → Read"),
        ("blueprints:create", "Deployment → Blueprints → Create")
    ]

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Connect to Jamf",
                message: """
                Pick where the configuration profiles are read from. Creating \
                blueprints is a Platform API capability, so a direct Jamf Pro \
                connection can only scan.
                """
            )

            Form {
                methodSection

                switch model.settings.method {
                case .platformAPI:
                    platformSection
                    if !model.settings.platform.scopeKind.reachesBlueprints {
                        tenantScopeWarning
                    }
                    permissionsSection
                case .jamfPro:
                    jamfProSection
                    scanOnlyNotice
                    privilegesSection
                }

                Section {
                    Toggle("Remember on this Mac", isOn: $model.rememberCredentials)
                } footer: {
                    Text("Secrets and passwords are kept in your login keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.isConnected { statusSection }
            }
            .formStyle(.grouped)
        }
        // A live connection belongs to the method that opened it, so switching
        // drops it rather than leaving a stale one behind the new form.
        .onChange(of: model.settings.method) { _, _ in
            if model.isConnected { model.signOut() }
        }
    }

    // MARK: - Method

    private var methodSection: some View {
        Section {
            Picker("Connect using", selection: $model.settings.method) {
                ForEach(ConnectionMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.settings.method.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Platform API

    private var platformSection: some View {
        Section {
            Picker("Region", selection: $model.settings.platform.region) {
                ForEach(JamfRegion.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            Picker("Scope", selection: $model.settings.platform.scopeKind) {
                ForEach(JamfScopeKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            TextField(
                model.settings.platform.scopeKind.fieldPrompt,
                text: $model.settings.platform.scopeID,
                prompt: Text("UUID from Jamf Account")
            )
            TextField("Client ID", text: $model.settings.platform.clientID)
            SecureField("Client secret", text: $model.settings.platform.clientSecret)
        } header: {
            Text("Platform API integration")
        } footer: {
            Text(
                """
                Created in Jamf Account under Integrations. Both scopes are Jamf \
                Account integrations; neither uses a Jamf Pro API role. The \
                gateway is reached at \
                \(model.settings.platform.region.host.absoluteString).
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var tenantScopeWarning: some View {
        Section {
            Label {
                Text(
                    """
                    Blueprints are published at environment scope only. A \
                    tenant-scoped integration can scan profiles but cannot create \
                    a blueprint.
                    """
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
        }
    }

    private var permissionsSection: some View {
        Section("Permissions the integration needs") {
            ForEach(platformPermissions, id: \.0) { permission in
                LabeledContent {
                    Text(permission.1)
                        .foregroundStyle(.secondary)
                } label: {
                    Text(permission.0)
                        .font(.callout.monospaced())
                }
            }
        }
    }

    // MARK: - Jamf Pro

    private var jamfProSection: some View {
        Section {
            TextField(
                "Server URL",
                text: $model.settings.pro.urlString,
                prompt: Text("your.jamfcloud.com")
            )

            Picker("Authenticate with", selection: $model.settings.pro.authKind) {
                ForEach(JamfProAuthKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.settings.pro.authKind.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch model.settings.pro.authKind {
            case .apiClient:
                TextField("Client ID", text: $model.settings.pro.clientID)
                SecureField("Client secret", text: $model.settings.pro.clientSecret)
            case .localAccount:
                TextField("User name", text: $model.settings.pro.username)
                SecureField("Password", text: $model.settings.pro.password)
            }
        } header: {
            Text("Jamf Pro server")
        }
    }

    private var scanOnlyNotice: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan only")
                        .font(.callout.weight(.medium))
                    Text(
                        """
                        This connection lists the profiles that grant Accessibility \
                        through the legacy PPPC payload, which is what you need to \
                        see what has to move. Creating the blueprints needs a \
                        Platform API integration, because blueprints are not part \
                        of the Jamf Pro API.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    private var privilegesSection: some View {
        Section("Privileges the account needs") {
            LabeledContent {
                Text("Settings → API roles and clients")
                    .foregroundStyle(.secondary)
            } label: {
                Text("Read macOS Configuration Profiles")
                    .font(.callout)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            if model.isScanning {
                LabeledContent("Scanning profiles") {
                    HStack(spacing: 8) {
                        ProgressView(
                            value: Double(model.scanned),
                            total: Double(max(model.scanTotal, 1))
                        )
                        .frame(width: 140)
                        Text("\(model.scanned) / \(model.scanTotal)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LabeledContent(
                    "Profiles with Accessibility",
                    value: "\(model.convertibleFindings.count)"
                )
            }

            if let available = model.nativeComponentAvailable {
                LabeledContent("App Settings component") {
                    Label(
                        available ? "Available" : "Not offered by this tenant",
                        systemImage: available ? "checkmark.circle.fill" : "minus.circle"
                    )
                    .foregroundStyle(available ? .green : .orange)
                }
            }

            if !model.canCreateBlueprints {
                LabeledContent("Blueprints") {
                    Label("Not available on this connection", systemImage: "minus.circle")
                        .foregroundStyle(.orange)
                }
            }

            Button("Forget Credentials", role: .destructive) {
                model.forgetCredentials()
            }
        }
    }
}
