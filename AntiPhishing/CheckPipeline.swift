//
//  CheckPipeline.swift
//  AntiPhishing
//
//  The shared check pipeline used by the dashboard, QR scanner, and
//  Share Extension — equivalent to the logic inside LinkInterceptorActivity
//  and QrScannerActivity on Android.
//
//  Step 1: Check URL against local lists (IS_LOCAL) or the Flask server.
//  Step 2: For Unknown results, run on-device LexicalAnalyzer.
//          - isObviouslyMalicious  → block immediately (Malicious)
//          - otherwise             → Step 3 ML server (not built yet) → Unknown
//

import Foundation

/// Set to true to use local URL lists instead of the Flask server
/// (matches `const val IS_LOCAL = true` on Android).
let IS_LOCAL = true

enum CheckPipeline {

    /// Runs the full pipeline for a URL and returns a CheckResult.
    /// `useQrEndpoint` selects the /api/qr/check endpoint when running against the server.
    static func check(_ url: String, useQrEndpoint: Bool = false) async -> CheckResult {

        // Step 1
        let serverResult: CheckResult
        if IS_LOCAL {
            serverResult = checkLocalLists(url)
        } else {
            serverResult = useQrEndpoint
                ? await ApiClient.checkQrUrl(url)
                : await ApiClient.checkUrl(url)
        }

        // Step 2: lexical analysis for Unknown links
        guard case .unknown = serverResult else {
            return serverResult
        }

        let lexical = LexicalAnalyzer.analyze(url)

        if lexical.isObviouslyMalicious {
            // Unambiguous signal — block immediately, no ML server call needed.
            return .malicious(
                explanation: lexical.flags.prefix(3).joined(separator: "\n"),
                source: "Lexical Analysis",
                confidence: 95,
                matchType: "lexical"
            )
        } else {
            // Step 3 (ML model) not built yet.
            let riskScore = Int(lexical.features["lexical_risk_score"] ?? 0)
            return .unknown(explanation:
                "Lexical analysis complete (score: \(riskScore)). " +
                "Step 3 ML model not built yet — cannot make final decision."
            )

            // When the ML server is ready, replace the above with:
            // return await ApiClient.scoreLexical(url, features: lexical.features)
        }
    }

    /// Used in dev/local mode instead of hitting the Flask server.
    static func checkLocalLists(_ url: String) -> CheckResult {
        switch LocalUrlLists.check(url) {
        case .whitelisted(let domain, _):
            _ = domain
            return .whitelisted(description: "Local whitelist match", category: "local_whitelist")
        case .blacklisted(let domain, let explanation):
            return .malicious(
                explanation: explanation,
                source: "Local blacklist: \(domain)",
                confidence: 100,
                matchType: "local_domain"
            )
        case .unknown:
            return .unknown(explanation: "No match in local whitelist or blacklist.")
        }
    }

    /// Builds a ScannedLink history entry from a result (mirrors saveToLocalDb).
    static func makeHistoryEntry(url: String, result: CheckResult) -> ScannedLink {
        let isSuspicious: Bool
        let riskScore: Int
        let threatType: String?

        switch result {
        case .whitelisted:
            isSuspicious = false; riskScore = 0; threatType = nil
        case .malicious(_, let source, let confidence, _):
            isSuspicious = true; riskScore = confidence; threatType = source
        case .unknown:
            isSuspicious = false; riskScore = 50; threatType = nil
        case .error:
            isSuspicious = false; riskScore = 50; threatType = nil
        }

        return ScannedLink(url: url, isSuspicious: isSuspicious, riskScore: riskScore, threatType: threatType)
    }

    // MARK: URL extraction (port of extractUrlFromText)

    static func extractUrlFromText(_ text: String) -> String? {
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pattern = #"https?://\S+|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:/\S*)?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        var raw = String(text[range])
        while let last = raw.last, ".,;)]}".contains(last) { raw.removeLast() }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return raw
        }
        return "https://\(raw)"
    }
}
