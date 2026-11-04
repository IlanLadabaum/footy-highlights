import Foundation
import Observation
import Sparkle

/// In-app updates via Sparkle: checks GitHub Releases once a day on launch and asks before installing.
/// Because the app downloads the update itself, macOS doesn't quarantine it, so users approve
/// "Open Anyway" only on first install. Updates are verified with the EdDSA public key in Info.plist.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    /// Nil when updates are off: Debug builds, developer test modes, or no public key in Info.plist yet.
    private let controller: SPUStandardUpdaterController?
    private(set) var canCheck = false
    private var observation: NSKeyValueObservation?

    /// Why "Check for Updates…" is unavailable, for Settings.
    var unavailableReason: String? {
        guard controller == nil else { return nil }
        #if DEBUG
            return "Updates are off in developer builds."
        #else
            return "Updates aren't set up in this build."
        #endif
    }

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        #if DEBUG
            let enabled = false
        #else
            let enabled = !key.isEmpty && AppModel.automaticRefresh
        #endif
        guard enabled else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheck = value }
        }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
