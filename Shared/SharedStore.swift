//
//  SharedStore.swift
//  AntiPhishing (Shared)
//
//  THE single shared-storage layer for everything that must be visible to both
//  the main app and the Safari Web Extension through the App Group container.
//
//  Nothing else in the project should build App Group paths or open shared
//  files directly — the app's updater, the UI, and the extension's native
//  handler all go through this type. It owns:
//
//    • the App Group identifier
//    • the on-disk layout of the protection data:
//         <container>/Protection/protection.sqlite   ← malicious-domain DB
//         <container>/Protection/metadata.json       ← ProtectionMetadata
//         <container>/Protection/allowlist.json      ← user approvals
//         <container>/Protection/staging/            ← update build area
//    • small shared flags in the group UserDefaults (protection switch,
//      extension heartbeat)
//
//  Compiled into BOTH the app target and the AntiPhishingWebExtension target.
//

import Foundation

/// `nonisolated`: the app target compiles with default-MainActor isolation,
/// but this layer is used from background update tasks and from the extension
/// process, so it must stay callable from any executor.
nonisolated enum SharedStore {

    /// App Group shared by the app, the Share Extension and the Safari Web
    /// Extension. Must match every target's entitlements file.
    static let appGroupID = "group.ronyahav.antiphishing"

    // Keys in the shared UserDefaults suite.
    private static let heartbeatKey = "safari_extension_last_seen_at"
    private static let protectionActiveKey = "is_active" // written by AppSettings
    private static let checkToastKey = "show_check_toast"

    // MARK: Container layout

    /// Root of the App Group container, or nil when the entitlement is missing
    /// (callers surface this as the "shared storage unavailable" state).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var protectionDirectoryURL: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("Protection", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The active malicious-domain SQLite database (read by app + extension).
    static var databaseURL: URL? {
        protectionDirectoryURL?.appendingPathComponent("protection.sqlite")
    }

    /// Scratch area used while building a new database during an update.
    /// The active database is never touched until the staged one is validated.
    static var stagingDirectoryURL: URL? {
        guard let dir = protectionDirectoryURL else { return nil }
        let staging = dir.appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// Last successfully downloaded raw copy of each threat feed. Lets an
    /// update reuse unchanged feeds (HTTP 304) or bridge a temporarily
    /// failing feed without dropping its domains from the rebuilt database.
    static var feedCacheDirectoryURL: URL? {
        guard let dir = protectionDirectoryURL else { return nil }
        let cache = dir.appendingPathComponent("feedcache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache
    }

    static var metadataURL: URL? {
        protectionDirectoryURL?.appendingPathComponent("metadata.json")
    }

    static var allowlistURL: URL? {
        protectionDirectoryURL?.appendingPathComponent("allowlist.json")
    }

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: Protection metadata

    /// Metadata describing the currently active protection database.
    /// Returns nil when no database has ever been activated (first launch).
    static func loadMetadata() -> ProtectionMetadata? {
        guard let url = metadataURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ProtectionMetadata.decoder.decode(ProtectionMetadata.self, from: data)
    }

    /// Atomically persists metadata. Written only after a database was
    /// successfully activated (or to record a failed update attempt).
    static func saveMetadata(_ metadata: ProtectionMetadata) throws {
        guard let url = metadataURL else { throw SharedStoreError.containerUnavailable }
        let data = try ProtectionMetadata.encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    /// True when an activated database file exists on disk.
    static var databaseExists: Bool {
        guard let url = databaseURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: Shared flags

    /// The app's master protection switch (owned by AppSettings in the app).
    /// The extension honors it so "Protection off" really turns checks off.
    static var isProtectionActive: Bool {
        sharedDefaults?.bool(forKey: protectionActiveKey) ?? false
    }

    /// "Show check confirmation in Safari" toggle (set in the app's Safari
    /// Protection screen). When on, the extension shows a small toast the
    /// first time each domain is checked against the local database — a
    /// user-visible way to confirm the protection is actually running.
    /// Repeat visits served from the extension's safe cache stay silent.
    static var isCheckToastEnabled: Bool {
        get { sharedDefaults?.bool(forKey: checkToastKey) ?? false }
        set { sharedDefaults?.set(newValue, forKey: checkToastKey) }
    }

    /// The Safari extension has no API the app can query for "is it enabled",
    /// so the native handler stamps a heartbeat every time Safari invokes it.
    /// The app uses a recent heartbeat as evidence the extension is enabled.
    static func recordExtensionHeartbeat() {
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
    }

    static var lastExtensionHeartbeat: Date? {
        guard let t = sharedDefaults?.object(forKey: heartbeatKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: t)
    }
}

nonisolated enum SharedStoreError: Error {
    case containerUnavailable
}
