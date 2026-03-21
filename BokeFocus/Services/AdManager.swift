import AppTrackingTransparency
import os
import SwiftUI

// MARK: - Ad Unit IDs

enum AdUnitID {
    static let interstitial = "ca-app-pub-9569882864362674/5337870667"
}

// MARK: - Ad Manager (Stub — GoogleMobileAds removed until AdMob app is activated)

@Observable
final class AdManager: NSObject {
    static let shared = AdManager()
    private static let logger = Logger(subsystem: "com.imaiissatsu.BokeFocus", category: "AdManager")

    private(set) var isInterstitialReady = false

    override private init() {
        super.init()
    }

    /// Request ATT permission, then initialize ads (stub until AdMob is activated)
    func configure() {
        Task { @MainActor in
            // Wait briefly for UI to settle before showing ATT prompt
            if #available(iOS 17.5, *) {
                try? await Task.sleep(for: .seconds(1))
            }

            let status = await ATTrackingManager.requestTrackingAuthorization()
            Self.logger.info("ATT status: \(status.rawValue)")

            // TODO: Uncomment when AdMob app is activated in console
            // await MobileAds.shared.start()
            // loadInterstitial()
        }
    }

    func loadInterstitial() {
        guard !StoreManager.shared.isAdRemoved else { return }
        // Stub — no-op until AdMob SDK is linked
    }

    func showInterstitial() {
        guard !StoreManager.shared.isAdRemoved else { return }
        // Stub — no-op until AdMob SDK is linked
    }
}
