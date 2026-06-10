//
//  ContentView.swift
//  AntiPhishing
//
//  Main dashboard — port of MainActivity.kt.
//  Shows the animated shield, protection toggle, stats, QR scanner button,
//  a manual link-check field (iOS-friendly equivalent of link interception),
//  recent activity, the "open safe links in" selector, and language toggle.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var history = HistoryStore.shared

    @State private var showScanner = false
    @State private var manualLink = ""
    @State private var checkUrl: String?     // drives the result sheet

    private var lang: AppLanguage { settings.language }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)
                    SecurityShield()
                    Spacer().frame(height: 16)

                    Text(settings.isProtectionActive
                         ? L10n.string("system_protected", lang)
                         : L10n.string("protection_disabled", lang))
                        .font(.title3).bold()
                        .foregroundStyle(settings.isProtectionActive ? AppColors.primary : .red)

                    Spacer().frame(height: 24)

                    // Stats
                    HStack(spacing: 16) {
                        StatCard(label: L10n.string("stats_scanned_today", lang),
                                 value: "\(history.todayScannedCount)",
                                 color: AppColors.primary)
                        StatCard(label: L10n.string("stats_threats_blocked", lang),
                                 value: "\(history.blockedThreatsCount)",
                                 color: .red)
                    }

                    Spacer().frame(height: 24)

                    // Master protection switch
                    HStack {
                        Text(L10n.string("active_protection", lang))
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $settings.isProtectionActive).labelsHidden()
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer().frame(height: 16)

                    // Manual link check (iOS-friendly interception equivalent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("check_link", lang)).font(.subheadline).bold()
                        HStack {
                            TextField(L10n.string("paste_link", lang), text: $manualLink)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.string("check_button", lang)) {
                                if let u = CheckPipeline.extractUrlFromText(manualLink) {
                                    checkUrl = u
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualLink.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer().frame(height: 16)

                    // QR scanner button — disabled when protection is off
                    Button {
                        if settings.isProtectionActive {
                            showScanner = true
                        }
                    } label: {
                        Text("📷  " + L10n.string("scan_qr", lang))
                            .bold()
                            .frame(maxWidth: .infinity).frame(height: 52)
                    }
                    .background(settings.isProtectionActive ? AppColors.primary : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer().frame(height: 32)

                    // Recent activity
                    Text(L10n.string("recent_activity", lang))
                        .font(.title3).bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(height: 8)

                    ForEach(history.recentLinks) { link in
                        RecentLinkItem(link: link) { history.deleteLink(id: link.id) }
                    }

                    Spacer().frame(height: 32)
                    Divider()
                    Spacer().frame(height: 16)

                    // "Open safe links in" selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("target_browser_label", lang))
                            .font(.subheadline).bold()
                        Picker("", selection: $settings.openInSafari) {
                            Text(L10n.string("open_in_safari", lang)).tag(true)
                            Text(L10n.string("open_in_app", lang)).tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(height: 16)

                    Button(role: .destructive) {
                        history.clearHistory()
                    } label: {
                        Label(L10n.string("clear_history", lang), systemImage: "trash")
                            .foregroundStyle(.gray)
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(L10n.string("app_name", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        settings.toggleLanguage()
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
        }
        .environment(\.layoutDirection, lang == .hebrew ? .rightToLeft : .leftToRight)
        .environmentObject(settings)
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(onClose: { showScanner = false })
                .environmentObject(settings)
        }
        .sheet(item: Binding(
            get: { checkUrl.map { IdentifiableURL(value: $0) } },
            set: { checkUrl = $0?.value }
        )) { item in
            LinkCheckView(
                url: item.value,
                onDismiss: { checkUrl = nil; manualLink = "" },
                onOpen: { URLOpener.open($0); checkUrl = nil; manualLink = "" }
            )
            .environmentObject(settings)
        }
    }
}

struct IdentifiableURL: Identifiable {
    let value: String
    var id: String { value }
}

#Preview {
    ContentView()
}
