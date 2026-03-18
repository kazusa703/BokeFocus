import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = StoreManager.shared

    private let privacyURL = URL(string: "https://kazusa703.github.io/BokeFocus/privacy-policy.html")!
    private let termsURL = URL(string: "https://kazusa703.github.io/BokeFocus/terms.html")!
    private let supportURL = URL(string: "https://kazusa703.github.io/BokeFocus/support.html")!

    var body: some View {
        NavigationStack {
            List {
                // Ad removal IAP
                if !store.isAdRemoved {
                    Section {
                        Button {
                            Task { await store.purchaseRemoveAds() }
                        } label: {
                            HStack {
                                Label(L.removeAds, systemImage: "xmark.circle")
                                Spacer()
                                if store.isPurchasing {
                                    ProgressView()
                                } else if let product = store.removeAdsProduct {
                                    Text(product.displayPrice)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(store.isPurchasing)

                        Button(L.restorePurchase) {
                            Task { await store.restore() }
                        }
                    }
                } else {
                    Section {
                        Label(L.adsRemoved, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Link(destination: privacyURL) {
                        Label(L.privacyPolicy, systemImage: "hand.raised")
                    }
                    Link(destination: termsURL) {
                        Label(L.termsOfUse, systemImage: "doc.text")
                    }
                    Link(destination: supportURL) {
                        Label(L.support, systemImage: "questionmark.circle")
                    }
                }

                Section {
                    HStack {
                        Text(L.version)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}
