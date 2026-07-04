//
//  ProtectionCenter.swift
//  AntiPhishing
//
//  Observable coordinator between the protection engine and the UI. Owns the
//  user-visible protection state machine and triggers launch checks and
//  manual updates. All the states required by the product spec map onto
//  `summary` below:
//
//    • extension not enabled            → extensionDetected == false
//    • extension on, no database        → .notReady
//    • database outdated                → .activeUpdateAvailable / stale flag
//    • active with current data         → .active
//    • active offline with old data     → .activeOffline
//    • update in progress               → .updating
//    • update failed, old DB active     → .updateFailedDatabaseActive
//    • no internet and no database      → .notReadyOffline
//    • shared storage / DB failure      → .storageError
//

import Foundation
import Combine

@MainActor
final class ProtectionCenter: ObservableObject {

    static let shared = ProtectionCenter()

    // MARK: State published to SwiftUI

    /// Metadata of the active database (nil until the first successful update).
    @Published private(set) var metadata: ProtectionMetadata?
    /// Live row count read from the database file itself.
    @Published private(set) var localDomainCount: Int?
    /// Latest /api/stats snapshot from this session; nil = server not reached.
    @Published private(set) var serverStats: ServerStats?
    /// False after a failed connectivity attempt, true after a success,
    /// nil before the first attempt finishes.
    @Published private(set) var serverReachable: Bool?
    /// Timestamp of the last Safari-extension native call (heartbeat).
    @Published private(set) var extensionLastSeen: Date?
    @Published private(set) var updateActivity: UpdateActivity = .idle
    /// Friendly outcome line for the last finished update ("1 minute ago…").
    @Published private(set) var lastUpdateOutcomeKey: String?

    enum UpdateActivity: Equatable {
        case idle
        case checking
        case updating(phaseKey: String, detail: String?)

        var isBusy: Bool { self != .idle }
    }

    /// One coarse state for the status card.
    enum Summary: Equatable {
        case storageError
        case masterOff              // app's master protection switch is off
        case updating
        case notReady               // no DB, connectivity unknown/ok
        case notReadyOffline        // no DB and server+feeds unreachable
        case active                 // DB present, believed current
        case activeUpdateAvailable  // DB present, server counters moved on
        case activeStale            // DB present but old (no recent check)
        case activeOffline          // DB present, currently offline
        case updateFailedDatabaseActive
    }

    /// Database older than this without a successful check is shown as
    /// "using an older database" (the server reseeds feeds every 12h).
    static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    /// Heartbeat window in which we consider the extension "enabled".
    /// There is no iOS API to query Safari extension state directly, so a
    /// recent native-handler call is the only reliable evidence.
    static let extensionSeenWindow: TimeInterval = 14 * 24 * 60 * 60

    private var didRunLaunchCheck = false

    private init() {
        refreshLocalState()
    }

    // MARK: Derived state

    var storageAvailable: Bool { SharedStore.containerURL != nil }
    var databaseExists: Bool { SharedStore.databaseExists }

    /// True when the Safari extension has called home recently enough.
    var extensionDetected: Bool {
        guard let seen = extensionLastSeen else { return false }
        return Date().timeIntervalSince(seen) < Self.extensionSeenWindow
    }

    /// Server counters moved since our snapshot → newer data is available.
    var updateAvailable: Bool {
        guard let stats = serverStats,
              let snapshot = metadata?.serverMaliciousDomains else { return false }
        return stats.maliciousDomains != snapshot
    }

    var summary: Summary {
        if !storageAvailable { return .storageError }
        if case .updating = updateActivity { return .updating }
        if updateActivity == .checking, !databaseExists { return .updating }
        // The extension honors the app's master switch (verdict "off"), so
        // the status must say so instead of claiming active protection.
        if !AppSettings.shared.isProtectionActive { return .masterOff }

        guard databaseExists, metadata != nil else {
            return serverReachable == false ? .notReadyOffline : .notReady
        }
        // A database is active from here on.
        if metadata?.lastUpdateError != nil { return .updateFailedDatabaseActive }
        if serverReachable == false { return .activeOffline }
        if updateAvailable { return .activeUpdateAvailable }
        if let updated = metadata?.updatedAt,
           Date().timeIntervalSince(updated) > Self.staleAfter {
            return .activeStale
        }
        return .active
    }

    // MARK: Actions

    /// Re-reads everything shared from disk (called on appear/foreground —
    /// the extension may have stamped its heartbeat or added allowlist
    /// entries while the app was inactive).
    func refreshLocalState() {
        metadata = SharedStore.loadMetadata()
        extensionLastSeen = SharedStore.lastExtensionHeartbeat
        if let dbURL = SharedStore.databaseURL, SharedStore.databaseExists {
            let db = ProtectionDatabase(url: dbURL)
            localDomainCount = db.domainCount()
            db.close()
        } else {
            localDomainCount = nil
        }
    }

    /// First-launch / app-open behavior:
    ///   • no local database → download it now (full update),
    ///   • database exists   → lightweight /api/stats check only; big
    ///     downloads never run implicitly when data is already present.
    func runLaunchCheckIfNeeded() async {
        guard !didRunLaunchCheck else { return }
        didRunLaunchCheck = true
        refreshLocalState()

        guard storageAvailable else { return }
        if !databaseExists {
            await startUpdate(force: false)
        } else {
            updateActivity = .checking
            let stats = await ApiClient.fetchStats()
            serverStats = stats
            serverReachable = stats != nil
            if stats != nil, var m = metadata {
                m.lastCheckedAt = Date()
                try? SharedStore.saveMetadata(m)
                metadata = m
            }
            updateActivity = .idle
        }
    }

    /// The "Update Protection Database" action (also used for the automatic
    /// first download). Runs the engine off the main actor and reflects
    /// progress into the UI.
    func startUpdate(force: Bool) async {
        guard !updateActivity.isBusy else { return }
        guard storageAvailable else { return }
        lastUpdateOutcomeKey = nil
        updateActivity = .updating(phaseKey: "sp_phase_contacting", detail: nil)

        do {
            let outcome = try await ProtectionUpdateEngine.performUpdate(force: force) { phase in
                Task { @MainActor in
                    ProtectionCenter.shared.reflect(phase: phase)
                }
            }
            switch outcome {
            case .updated(let newMetadata):
                metadata = newMetadata
                lastUpdateOutcomeKey = "sp_update_success"
            case .alreadyUpToDate(let newMetadata):
                metadata = newMetadata
                lastUpdateOutcomeKey = "sp_update_already_current"
            }
            serverReachable = true
        } catch let error as ProtectionUpdateEngine.UpdateError {
            ProtectionUpdateEngine.recordFailure(error)
            lastUpdateOutcomeKey = friendlyErrorKey(for: error)
            if case .noFeedData = error { serverReachable = false }
        } catch {
            lastUpdateOutcomeKey = "err_update_generic"
        }

        updateActivity = .idle
        refreshLocalState()
        serverStats = await ApiClient.fetchStats() ?? serverStats
        if serverStats != nil { serverReachable = true }
    }

    private func reflect(phase: ProtectionUpdateEngine.Phase) {
        switch phase {
        case .contactingServer:
            updateActivity = .updating(phaseKey: "sp_phase_contacting", detail: nil)
        case .downloading(let feed, let index, let total):
            updateActivity = .updating(phaseKey: "sp_phase_downloading", detail: "\(index)/\(total) · \(feed)")
        case .building:
            updateActivity = .updating(phaseKey: "sp_phase_building", detail: nil)
        case .validating:
            updateActivity = .updating(phaseKey: "sp_phase_validating", detail: nil)
        case .activating:
            updateActivity = .updating(phaseKey: "sp_phase_activating", detail: nil)
        }
    }

    /// Maps engine errors to friendly, localized message keys. Raw details
    /// stay in metadata.lastUpdateError for debugging only.
    private func friendlyErrorKey(for error: ProtectionUpdateEngine.UpdateError) -> String {
        switch error {
        case .storageUnavailable: return "err_update_storage"
        case .noFeedData: return databaseExists ? "err_update_offline_db" : "err_update_offline_nodb"
        case .tooFewDomains, .validationFailed: return "err_update_invalid_data"
        case .buildFailed, .activationFailed: return "err_update_generic"
        }
    }
}
