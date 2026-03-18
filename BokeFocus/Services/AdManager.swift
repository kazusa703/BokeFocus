import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit

// MARK: - Ad Unit IDs

enum AdUnitID {
    static let interstitial = "ca-app-pub-9569882864362674/5337870667"
}

// MARK: - Ad Manager

@Observable
final class AdManager: NSObject {
    static let shared = AdManager()

    private(set) var isInterstitialReady = false
    private var interstitialAd: GoogleMobileAds.InterstitialAd?

    override private init() {
        super.init()
    }

    /// Request ATT permission then initialize Google Mobile Ads SDK
    func configure() {
        Task { @MainActor in
            if #available(iOS 17.5, *) {
                try? await Task.sleep(for: .seconds(1))
            }

            let status = await ATTrackingManager.requestTrackingAuthorization()
            print("[AdManager] ATT status: \(status.rawValue)")

            await MobileAds.shared.start()
            loadInterstitial()
        }
    }

    // MARK: - Interstitial

    func loadInterstitial() {
        guard !StoreManager.shared.isAdRemoved else { return }

        let request = GoogleMobileAds.Request()
        GoogleMobileAds.InterstitialAd.load(
            with: AdUnitID.interstitial,
            request: request
        ) { [weak self] ad, error in
            if let error {
                print("[AdManager] Interstitial load failed: \(error.localizedDescription)")
                return
            }
            self?.interstitialAd = ad
            self?.interstitialAd?.fullScreenContentDelegate = self
            self?.isInterstitialReady = true
        }
    }

    func showInterstitial() {
        guard !StoreManager.shared.isAdRemoved else { return }
        guard let ad = interstitialAd else {
            loadInterstitial()
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
            let root = windowScene.windows.first?.rootViewController
        else { return }

        ad.present(from: root)
        isInterstitialReady = false
        interstitialAd = nil
    }
}

// MARK: - FullScreenContentDelegate

extension AdManager: @preconcurrency FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_: any FullScreenPresentingAd) {
        loadInterstitial()
    }
}
