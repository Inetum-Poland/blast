//
//  CredentialStore.swift
//  BLAST
//

import Foundation
import Security

/// Keeps the non-secret parts of a connection in user defaults and every secret
/// in the keychain.
nonisolated enum CredentialStore {
    private static let service = "com.inetum.BLAST.credentials"

    private enum Key {
        static let method = "connection.method"
        static let region = "platform.region"
        static let scopeKind = "platform.scopeKind"
        static let scopeID = "platform.scopeID"
        static let clientID = "platform.clientID"
        static let proURL = "pro.url"
        static let proAuthKind = "pro.authKind"
        static let proClientID = "pro.clientID"
        static let proUsername = "pro.username"

        static let all = [
            method, region, scopeKind, scopeID, clientID,
            proURL, proAuthKind, proClientID, proUsername
        ]
    }

    /// Keychain accounts. Each secret is stored under its own identity so two
    /// connections do not overwrite one another.
    private enum Secret {
        static func platform(_ clientID: String) -> String { "platform:\(clientID)" }
        static func proClient(_ host: String, _ clientID: String) -> String {
            "pro-client:\(host):\(clientID)"
        }
        static func proAccount(_ host: String, _ username: String) -> String {
            "pro-account:\(host):\(username)"
        }
    }

    static func load() -> ConnectionSettings {
        let defaults = UserDefaults.standard
        var settings = ConnectionSettings()

        if let raw = defaults.string(forKey: Key.method),
           let method = ConnectionMethod(rawValue: raw) {
            settings.method = method
        }

        if let raw = defaults.string(forKey: Key.region), let region = JamfRegion(rawValue: raw) {
            settings.platform.region = region
        }
        if let raw = defaults.string(forKey: Key.scopeKind),
           let kind = JamfScopeKind(rawValue: raw) {
            settings.platform.scopeKind = kind
        }
        settings.platform.scopeID = defaults.string(forKey: Key.scopeID) ?? ""
        settings.platform.clientID = defaults.string(forKey: Key.clientID) ?? ""
        if !settings.platform.clientID.isEmpty {
            settings.platform.clientSecret =
                secret(account: Secret.platform(settings.platform.clientID)) ?? ""
        }

        settings.pro.urlString = defaults.string(forKey: Key.proURL) ?? ""
        if let raw = defaults.string(forKey: Key.proAuthKind),
           let kind = JamfProAuthKind(rawValue: raw) {
            settings.pro.authKind = kind
        }
        settings.pro.clientID = defaults.string(forKey: Key.proClientID) ?? ""
        settings.pro.username = defaults.string(forKey: Key.proUsername) ?? ""
        if let host = settings.pro.baseURL?.host() {
            if !settings.pro.clientID.isEmpty {
                settings.pro.clientSecret =
                    secret(account: Secret.proClient(host, settings.pro.clientID)) ?? ""
            }
            if !settings.pro.username.isEmpty {
                settings.pro.password =
                    secret(account: Secret.proAccount(host, settings.pro.username)) ?? ""
            }
        }
        return settings
    }

    static func save(_ settings: ConnectionSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.method.rawValue, forKey: Key.method)

        defaults.set(settings.platform.region.rawValue, forKey: Key.region)
        defaults.set(settings.platform.scopeKind.rawValue, forKey: Key.scopeKind)
        defaults.set(settings.platform.scopeID.trimmed, forKey: Key.scopeID)
        let platformClientID = settings.platform.clientID.trimmed
        defaults.set(platformClientID, forKey: Key.clientID)
        setSecret(
            settings.platform.clientSecret, account: Secret.platform(platformClientID)
        )

        defaults.set(settings.pro.urlString.trimmed, forKey: Key.proURL)
        defaults.set(settings.pro.authKind.rawValue, forKey: Key.proAuthKind)
        let proClientID = settings.pro.clientID.trimmed
        let proUsername = settings.pro.username.trimmed
        defaults.set(proClientID, forKey: Key.proClientID)
        defaults.set(proUsername, forKey: Key.proUsername)
        if let host = settings.pro.baseURL?.host() {
            setSecret(
                settings.pro.clientSecret, account: Secret.proClient(host, proClientID)
            )
            setSecret(
                settings.pro.password, account: Secret.proAccount(host, proUsername)
            )
        }
    }

    static func forget(_ settings: ConnectionSettings) {
        let defaults = UserDefaults.standard
        for key in Key.all { defaults.removeObject(forKey: key) }

        var accounts = [Secret.platform(settings.platform.clientID.trimmed)]
        if let host = settings.pro.baseURL?.host() {
            accounts.append(Secret.proClient(host, settings.pro.clientID.trimmed))
            accounts.append(Secret.proAccount(host, settings.pro.username.trimmed))
        }
        for account in accounts {
            SecItemDelete(query(account: account) as CFDictionary)
        }
    }

    // MARK: - Keychain

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func secret(account: String) -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func setSecret(_ secret: String, account: String) {
        guard !account.hasSuffix(":") else { return }
        let request = query(account: account)
        guard !secret.isEmpty else {
            SecItemDelete(request as CFDictionary)
            return
        }
        let data = Data(secret.utf8)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(request as CFDictionary, update as CFDictionary) == errSecSuccess {
            return
        }
        var insert = request
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(insert as CFDictionary, nil)
    }
}
