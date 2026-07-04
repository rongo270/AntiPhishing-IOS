//
//  SafariProtectionView.swift
//  AntiPhishing
//
//  Safari-protection dashboard: protection/database status, the
//  "Update Protection Database" action, the enable-the-extension guide, and
//  entry to the approved-domains (allowlist) screen.
//
//  Honesty rules baked into this screen:
//   • iOS provides no API to enable a Safari extension or query its state —
//     the user must enable it in Settings, so we only *guide* them there and
//     detect activity through the extension's heartbeat.
//   • The extension protects Safari only; if another browser is the default,
//     links open unprotected. We say so instead of overpromising.
//

import SwiftUI
import UIKit

/// Icon/color/copy for each protection state — shared by the dashboard card
/// in ContentView and the full status screen below.
extension ProtectionCenter.Summary {
    var visual: (icon: String, color: Color, titleKey: String, detailKey: String) {
        switch self {
        case .storageError:
            return ("exclamationmark.octagon.fill", .red, "sp_status_storage_error", "sp_status_storage_error_detail")
        case .masterOff:
            return ("shield.slash.fill", .red, "protection_disabled", "sp_master_off_detail")
        case .updating:
            return ("arrow.triangle.2.circlepath", AppColors.primary, "sp_status_updating", "sp_status_updating_detail")
        case .notReady:
            return ("shield.slash.fill", .orange, "sp_status_no_db", "sp_status_no_db_detail")
        case .notReadyOffline:
            return ("wifi.slash", .red, "sp_status_no_db_offline", "sp_status_no_db_offline_detail")
        case .active:
            return ("checkmark.shield.fill", .green, "sp_status_active", "sp_status_active_detail")
        case .activeUpdateAvailable:
            return ("shield.lefthalf.filled", AppColors.primary, "sp_status_update_available", "sp_status_update_available_detail")
        case .activeStale:
            return ("clock.badge.exclamationmark", .orange, "sp_status_active_stale", "sp_status_active_stale_detail")
        case .activeOffline:
            return ("wifi.slash", .orange, "sp_status_offline", "sp_status_offline_detail")
        case .updateFailedDatabaseActive:
            return ("exclamationmark.shield.fill", .orange, "sp_status_update_failed", "sp_status_update_failed_detail")
        }
    }
}

struct SafariProtectionView: View {
    @ObservedObject private var center = ProtectionCenter.shared
    @EnvironmentObject var settings: AppSettings

    @State private var showExtensionGuide = false
    @Environment(\.scenePhase) private var scenePhase

    private var lang: AppLanguage { settings.language }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                extensionCard
                databaseCard
                allowlistCard
                safariOnlyNote
            }
            .padding(20)
        }
        .navigationTitle(L10n.string("safari_protection_title", lang))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExtensionGuide) {
            SafariExtensionGuideView()
                .environmentObject(settings)
        }
        .onAppear { center.refreshLocalState() }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings/Safari — the heartbeat may be fresh now.
            if phase == .active { center.refreshLocalState() }
        }
        .environment(\.layoutDirection, lang == .hebrew ? .rightToLeft : .leftToRight)
    }

    // MARK: Status card

    private var statusCard: some View {
        let visual = center.summary.visual
        return VStack(spacing: 10) {
            Image(systemName: visual.icon)
                .font(.system(size: 44))
                .foregroundStyle(visual.color)
            Text(L10n.string(visual.titleKey, lang))
                .font(.headline)
                .multilineTextAlignment(.center)
            if case .updating(let phaseKey, let detail) = center.updateActivity {
                ProgressView().padding(.top, 2)
                Text(L10n.string(phaseKey, lang) + (detail.map { "\n\($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(L10n.string(visual.detailKey, lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let outcomeKey = center.lastUpdateOutcomeKey {
                Text(L10n.string(outcomeKey, lang))
                    .font(.footnote).bold()
                    .foregroundStyle(outcomeKey.hasPrefix("err_") ? .red : AppColors.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(visual.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Extension card

    private var extensionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: center.extensionDetected ? "puzzlepiece.extension.fill" : "puzzlepiece.extension")
                    .foregroundStyle(center.extensionDetected ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string(center.extensionDetected ? "sp_ext_enabled" : "sp_ext_not_detected", lang))
                        .font(.subheadline).bold()
                    if let seen = center.extensionLastSeen, center.extensionDetected {
                        Text(L10n.string("sp_ext_last_seen", lang) + " " + seen.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.string("sp_ext_not_detected_detail", lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Button {
                showExtensionGuide = true
            } label: {
                Text(L10n.string("sp_ext_guide_button", lang))
                    .font(.subheadline).bold()
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .background(AppColors.primary.opacity(0.12))
            .foregroundStyle(AppColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Database card

    private var databaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("sp_db_section", lang))
                .font(.subheadline).bold()

            if let metadata = center.metadata {
                infoRow("number", L10n.string("sp_db_version", lang), "\(metadata.version)")
                infoRow("calendar", L10n.string("sp_db_updated", lang),
                        metadata.updatedAt.formatted(date: .abbreviated, time: .shortened))
                infoRow("shield.checkered", L10n.string("sp_db_domains", lang),
                        (center.localDomainCount ?? metadata.domainCount).formatted())
                if let serverCount = center.serverStats?.maliciousDomains ?? metadata.serverMaliciousDomains {
                    infoRow("server.rack", L10n.string("sp_db_server_domains", lang), serverCount.formatted())
                }
                if let checked = metadata.lastCheckedAt {
                    infoRow("clock", L10n.string("sp_db_checked", lang),
                            checked.formatted(.relative(presentation: .named)))
                }
            } else {
                Text(L10n.string("sp_db_none", lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await center.startUpdate(force: center.metadata != nil) }
            } label: {
                HStack {
                    if center.updateActivity.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(L10n.string(center.metadata == nil ? "sp_download_button" : "sp_update_button", lang))
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .background(center.updateActivity.isBusy ? Color.gray : AppColors.primary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(center.updateActivity.isBusy)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.primary)
                .frame(width: 20)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote).bold()
        }
    }

    // MARK: Allowlist + note

    private var allowlistCard: some View {
        NavigationLink {
            AllowlistView().environmentObject(settings)
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.badge.questionmark")
                    .foregroundStyle(AppColors.primary)
                Text(L10n.string("allowlist_title", lang))
                    .font(.subheadline).bold()
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var safariOnlyNote: some View {
        Text(L10n.string("sp_note_safari_only", lang))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Enable-extension guide

/// Step-by-step sheet guiding the user to Settings ▸ Apps ▸ Safari ▸
/// Extensions. iOS deliberately keeps this a manual user action, so the most
/// an app may do is open the Settings app.
struct SafariExtensionGuideView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { settings.language }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.primary)
                    .padding(.top, 24)

                Text(L10n.string("ext_guide_title", lang))
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                Text(L10n.string("ext_guide_intro", lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    guideStep(1, L10n.string("ext_guide_step1", lang))
                    guideStep(2, L10n.string("ext_guide_step2", lang))
                    guideStep(3, L10n.string("ext_guide_step3", lang))
                    guideStep(4, L10n.string("ext_guide_step4", lang))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(L10n.string("ext_guide_note", lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    // Best deep link iOS offers: the app's own Settings page
                    // (Settings ▸ Apps ▸ AntiPhishing), one tap from Safari's
                    // extension list. There is no public URL directly into
                    // Safari's extension settings.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L10n.string("ext_guide_open_settings", lang)).bold()
                        .frame(maxWidth: .infinity).frame(height: 52)
                }
                .background(AppColors.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(L10n.string("close", lang)) { dismiss() }
                    .foregroundStyle(AppColors.primary)
            }
            .padding(24)
        }
        .environment(\.layoutDirection, lang == .hebrew ? .rightToLeft : .leftToRight)
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline).bold()
                .frame(width: 26, height: 26)
                .background(AppColors.primary.opacity(0.15))
                .clipShape(Circle())
                .foregroundStyle(AppColors.primary)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
