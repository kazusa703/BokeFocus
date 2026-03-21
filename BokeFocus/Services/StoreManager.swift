import os
import StoreKit
import SwiftUI

@Observable
final class StoreManager {
    static let shared = StoreManager()

    /// Product IDs
    static let removeAdsID = "com.imaiissatsu.BokeFocus.removeads"
    private static let logger = Logger(subsystem: "com.imaiissatsu.BokeFocus", category: "Store")

    var isAdRemoved: Bool = false
    var removeAdsProduct: Product?
    var isPurchasing = false

    private init() {
        Task { await loadProducts() }
        Task { await listenForTransactions() }
        Task { await checkEntitlements() }
    }

    // MARK: - Load products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.removeAdsID])
            removeAdsProduct = products.first
        } catch {
            Self.logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchaseRemoveAds() async {
        guard let product = removeAdsProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isAdRemoved = true
            case .pending:
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            Self.logger.error("Purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    func restore() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Check entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.removeAdsID
            {
                isAdRemoved = true
                return
            }
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == Self.removeAdsID {
                    isAdRemoved = true
                }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.unverified
        case let .verified(value):
            return value
        }
    }

    enum StoreError: Error {
        case unverified
    }
}
