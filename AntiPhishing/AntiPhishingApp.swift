//
//  AntiPhishingApp.swift
//  AntiPhishing
//

import SwiftUI

@main
struct AntiPhishingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Allows opening links via a custom URL scheme (antiphishing://check?url=...)
                    SharedLinkInbox.handleIncoming(url)
                }
        }
    }
}

/// Bridges links arriving from the Share Extension (via the shared App Group)
/// or a custom URL scheme into the running app.
enum SharedLinkInbox {
    static func handleIncoming(_ url: URL) {
        guard url.scheme == "antiphishing",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = comps.queryItems?.first(where: { $0.name == "url" })?.value else { return }
        UserDefaults(suiteName: HistoryStore.appGroup)?.set(target, forKey: "pending_shared_url")
    }
}
