import Foundation
import StoreKit

// Apple IAP (decided 2026-06-13): StoreKit 2 is the checkout — plans are
// auto-renewable subscriptions, credit packs are consumables. Every
// verified transaction's JWS goes to /api/billing/apple, which sets
// profiles.plan / tops up credit; renewals arrive server-side via App
// Store Server Notifications (appAccountToken = Supabase user id).
@MainActor
@Observable
final class StoreService {
    static let planProductIDs = [
        "dev.max5well.agentline.plus",
        "dev.max5well.agentline.pro",
        "dev.max5well.agentline.max",
    ]
    static let creditProductIDs = [
        "dev.max5well.agentline.credit5",
        "dev.max5well.agentline.credit10",
        "dev.max5well.agentline.credit20",
    ]

    private(set) var plans: [Product] = []
    private(set) var credits: [Product] = []
    private(set) var purchasingId: String?
    /// Product id of the active subscription on this Apple account.
    private(set) var activePlanProductId: String?
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    func start() async {
        // Unfinished transactions (e.g. the backend was unreachable when
        // the purchase landed) are redelivered here on every launch.
        updatesTask = updatesTask ?? Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update: update)
            }
        }
        await loadProducts()
        await syncEntitlements()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(
                for: Self.planProductIDs + Self.creditProductIDs
            )
            plans = products
                .filter { Self.planProductIDs.contains($0.id) }
                .sorted { $0.price < $1.price }
            credits = products
                .filter { Self.creditProductIDs.contains($0.id) }
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "App Store unavailable: \(error.localizedDescription)"
        }
    }

    /// Returns true when the purchase completed (not cancelled/pending).
    func purchase(_ product: Product) async -> Bool {
        purchasingId = product.id
        errorMessage = nil
        defer { purchasingId = nil }
        do {
            var options: Set<Product.PurchaseOption> = []
            // Lets App Store Server Notifications find the Supabase user.
            if let id = AuthStore.shared.session.flatMap({ UUID(uuidString: $0.userId) }) {
                options.insert(.appAccountToken(id))
            }
            switch try await product.purchase(options: options) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "Purchase could not be verified"
                    return false
                }
                // Backend first, finish after — an unfinished transaction
                // is redelivered via Transaction.updates, so a backend
                // outage can't swallow a credit purchase.
                let synced = await sync(jwsList: [verification.jwsRepresentation])
                if synced { await transaction.finish() }
                await syncEntitlements()
                return synced
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase pending approval (Ask to Buy)"
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        // StoreKit's AppStore, not the app's own AppStore store class.
        try? await StoreKit.AppStore.sync()
        await syncEntitlements()
    }

    /// Reports the full set of current entitlements; the backend treats
    /// "no active subscription" in a full sync as a lapse back to Free.
    func syncEntitlements() async {
        var jwsList: [String] = []
        var active: String?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            jwsList.append(entitlement.jwsRepresentation)
            if Self.planProductIDs.contains(transaction.productID) {
                active = transaction.productID
            }
        }
        activePlanProductId = active
        _ = await sync(jwsList: jwsList, fullSync: true)
    }

    private func handle(update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        let synced = await sync(jwsList: [update.jwsRepresentation])
        if synced { await transaction.finish() }
    }

    private func sync(jwsList: [String], fullSync: Bool = false) async -> Bool {
        guard let backend = AppStore.backendIfConfigured() else { return false }
        do {
            try await backend.appleSync(transactions: jwsList, fullSync: fullSync)
            return true
        } catch {
            errorMessage = "Purchase saved, syncing with the backend failed — it will retry."
            return false
        }
    }
}
