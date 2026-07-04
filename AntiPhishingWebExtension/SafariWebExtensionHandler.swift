//
//  SafariWebExtensionHandler.swift
//  AntiPhishingWebExtension
//
//  Native side of the Safari Web Extension. The extension's JavaScript cannot
//  read App Group files, so every protection decision funnels through this
//  handler via browser.runtime.sendNativeMessage:
//
//    {action: "checkDomain", url}   → verdict from the LOCAL database:
//                                     allowlist check → SQLite suffix lookup.
//                                     No network. No page URL ever leaves
//                                     the device from here.
//    {action: "allowDomain", domain}→ "Continue Anyway": stores a temporary
//                                     approval in the shared allowlist.
//    {action: "getStatus"}          → database/protection status for the
//                                     popup UI.
//
//  Shared code: SharedStore / ProtectionDatabase / DomainNormalizer /
//  AllowlistStore are the same source files the app compiles — both sides
//  normalize and look up domains identically by construction.
//
//  Every request also stamps a heartbeat in the shared defaults; the app uses
//  it as the only available evidence that the user enabled the extension
//  (iOS offers no API to query Safari extension state).
//

import SafariServices
import os.log

private let log = OSLog(subsystem: "com.rongo.AntiPhishing.WebExtension", category: "protection")

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    /// One read-only database handle per extension process. Reopened when the
    /// app activates a new database version (file replaced under us).
    private static var database: ProtectionDatabase?
    private static var databaseVersion: Int = -1

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        // Evidence for the app's "extension enabled" status row.
        SharedStore.recordExtensionHeartbeat()

        var response: [String: Any] = ["ok": false, "error": "unknown action"]
        if let dict = message as? [String: Any], let action = dict["action"] as? String {
            switch action {
            case "checkDomain":
                response = Self.handleCheckDomain(dict)
            case "allowDomain":
                response = Self.handleAllowDomain(dict)
            case "getStatus":
                response = Self.handleGetStatus()
            default:
                os_log(.default, log: log, "unknown native action: %{public}@", action)
            }
        }

        let item = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            item.userInfo = [SFExtensionMessageKey: response]
        } else {
            item.userInfo = ["message": response]
        }
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }

    // MARK: - Actions

    /// Local-only verdict for one page URL. Response verdicts:
    ///   "off"          protection switch disabled in the app
    ///   "unprotected"  no database downloaded yet / storage failure
    ///   "allowlisted"  covered by a user "Continue Anyway" approval
    ///   "malicious"    matched the malicious-domain database
    ///   "safe"         not in the database
    private static func handleCheckDomain(_ dict: [String: Any]) -> [String: Any] {
        guard let rawURL = dict["url"] as? String,
              let host = DomainNormalizer.normalizeHost(from: rawURL) else {
            return ["ok": false, "error": "invalid url"]
        }

        let metadata = SharedStore.loadMetadata()
        var response: [String: Any] = [
            "ok": true,
            "host": host,
            // The JS layer tags its verdict cache with this and drops entries
            // when the app activates a newer database.
            "dbVersion": metadata?.version ?? 0,
        ]

        guard SharedStore.isProtectionActive else {
            response["verdict"] = "off"
            return response
        }

        // User-approved domain (walks the same parent chain as the DB lookup).
        if let approval = AllowlistStore.activeEntry(forNormalizedHost: host) {
            response["verdict"] = "allowlisted"
            response["allowlistExpiresAt"] = approval.expiresAt.timeIntervalSince1970 * 1000
            return response
        }

        guard let db = openDatabase(currentVersion: metadata?.version ?? 0) else {
            response["verdict"] = "unprotected"
            return response
        }

        if let match = db.match(normalizedHost: host) {
            response["verdict"] = "malicious"
            response["matchedDomain"] = match.matchedDomain
            response["source"] = match.source
            response["threatType"] = match.threatType
        } else {
            response["verdict"] = "safe"
        }
        return response
    }

    /// Stores the user's "Continue Anyway" decision. `domain` is the matched
    /// (blocking) database entry so the approval covers the whole blocked
    /// site; expiry uses the shared default TTL (24h).
    private static func handleAllowDomain(_ dict: [String: Any]) -> [String: Any] {
        guard let domain = dict["domain"] as? String,
              let entry = AllowlistStore.approve(domain: domain) else {
            return ["ok": false, "error": "invalid domain"]
        }
        os_log(.info, log: log, "user approved domain until %{public}@", "\(entry.expiresAt)")
        return [
            "ok": true,
            "domain": entry.domain,
            "expiresAt": entry.expiresAt.timeIntervalSince1970 * 1000,
        ]
    }

    /// Status snapshot for the popup: does a database exist, how fresh is it,
    /// how many domains, is the master switch on.
    private static func handleGetStatus() -> [String: Any] {
        let metadata = SharedStore.loadMetadata()
        var response: [String: Any] = [
            "ok": true,
            "protectionActive": SharedStore.isProtectionActive,
            "databaseExists": SharedStore.databaseExists,
            "dbVersion": metadata?.version ?? 0,
        ]
        if let metadata {
            response["domainCount"] = metadata.domainCount
            response["updatedAt"] = metadata.updatedAt.timeIntervalSince1970 * 1000
        }
        return response
    }

    // MARK: - Database handle

    /// Returns an open handle on the active database, reopening after the
    /// app swapped the file for a newer version (the version lives in
    /// metadata.json, so comparing it is cheap and cross-process safe).
    private static func openDatabase(currentVersion: Int) -> ProtectionDatabase? {
        if let db = database, databaseVersion == currentVersion {
            return db
        }
        database?.close()
        database = nil
        guard let url = SharedStore.databaseURL, SharedStore.databaseExists else { return nil }
        let db = ProtectionDatabase(url: url)
        guard db.open() else { return nil }
        database = db
        databaseVersion = currentVersion
        return db
    }
}
