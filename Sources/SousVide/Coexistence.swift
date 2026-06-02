import SwiftUI
import AppKit
import Combine
import PanelKit
import SousShared
import SousKit

/// Detects whether Oxine — which has Sous built in — is also set up to manage
/// this Mac's battery. When it is, the standalone sous-vide is redundant: it's a
/// second Sous daemon contending for the machine-wide control lock, and only one
/// can drive the SMC at a time. Oxine is the canonical home, so sous-vide always
/// yields to it (never the other way round) and nudges the user to hand the
/// battery over and remove sous-vide.
@MainActor
final class CoexistenceMonitor: ObservableObject {
    static let shared = CoexistenceMonitor()

    /// True when Oxine's Sous daemon is installed alongside ours.
    @Published private(set) var oxineRunsSous = false
    /// Set when the user chose to keep sous-vide anyway this launch, so we stop
    /// nagging until the next launch.
    @Published var dismissedThisLaunch = false

    /// Show the take-over card iff Oxine's Sous is present and the user hasn't
    /// waved us off for this session.
    var shouldYield: Bool { oxineRunsSous && !dismissedThisLaunch }

    private init() { refresh() }

    /// Re-check on demand (cheap file-existence probe). Called on launch and each
    /// time the panel opens, so removing Oxine's Sous clears the card next open.
    func refresh() { oxineRunsSous = HelperBranding.oxine.isDaemonInstalled }
}

/// The deferral surface shown in place of the Sous controls when Oxine is also
/// running Sous. Frames the standalone as the redundant one and offers a clean
/// step-aside: release control, uninstall our own helper, and (optionally) move
/// the app to the Trash before quitting.
struct TakeoverCard: View {
    var onKeep: () -> Void
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.panelAccent, .white.opacity(0.85))
                .font(.system(size: 34, weight: .semibold))
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text("Oxine already runs Sous")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                Text("Oxine has battery care built in and it's managing this Mac. Two Sous helpers can't drive the battery at once, so sous-vide is standing by. Hand it to Oxine and remove sous-vide.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            VStack(spacing: 8) {
                Button(action: { stepAside(trashApp: true) }) {
                    HStack(spacing: 6) {
                        if working { ProgressView().controlSize(.small).tint(.black) }
                        Text(working ? "Removing\u{2026}" : "Remove sous-vide")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.panelAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundColor(.black.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(working)

                Button(action: { stepAside(trashApp: false) }) {
                    Text("Uninstall helper & quit")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
            .padding(.horizontal, 18)

            Button("Keep sous-vide anyway", action: onKeep)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .disabled(working)

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Release control, uninstall sous-vide's own daemon (one admin prompt), and
    /// quit — optionally moving the app to the Trash first. Failures surface
    /// inline rather than quitting half-done.
    private func stepAside(trashApp: Bool) {
        working = true
        errorText = nil
        Task {
            // Drop control immediately so Oxine's daemon can grab the lock.
            SousManager.shared.setEnabled(false)
            await SousManager.shared.helper.uninstall()
            if case .failed(let why) = SousManager.shared.helper.installState {
                working = false
                errorText = why
                return
            }
            if trashApp {
                try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
            }
            NSApp.terminate(nil)
        }
    }
}
