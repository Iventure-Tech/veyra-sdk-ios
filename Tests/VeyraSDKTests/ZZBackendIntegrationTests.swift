// LIVE-backend integration check (STORY-33 Phase 2): proves the full iOS chain —
// Swift facade → VeyraKMP → shared Kotlin service → OAuth token fetch → URLSession/Ktor →
// the real UAT backend. Uses the sample's committed demo credentials (same as the Android
// sample's config.xml) and read-only calls (token + bank lists) — nothing is created in UAT.
//
// 'ZZ' prefix: runs last (XCTest is alphabetical); it (re)configures the process-global
// singletons with TEST, so it must follow the notConfigured/local tests. Requires network —
// if UAT is unreachable the failure message says so explicitly.
import XCTest
import VeyraSoftPOS
import VeyraWallet

final class ZZBackendIntegrationTests: XCTestCase {

    private static let clientID = "sHeW3kMNqyUzX_muih7nI6fLtWMa"
    private static let clientSecret = "G3Lh3rbHa3GEVoo3cwgJUp3NXcY4FaCcuYl0r9AhUK0a"

    func testWalletBanksReachesUatEndToEnd() async throws {
        VeyraWallet.configure(
            .init(
                environment: .test,
                clientID: Self.clientID,
                clientSecret: Self.clientSecret,
                httpLoggingEnabled: true,
                appleTeamID: "TV4JRK677Z" // mandatory since STORY-36 slice 5 (sample app's team)
            )
        )
        let banks = try await VeyraWallet.shared.tokenisation.banks()
        XCTAssertFalse(banks.isEmpty, "UAT returned no banks — backend reachable but empty?")
        XCTAssertTrue(
            banks.contains { $0.institutionCode == "090325" },
            "expected Sparkle MFB (090325) in UAT banks, got: \(banks.map(\.institutionCode))"
        )
    }

    func testWalletEligibilityReachesUat() async throws {
        VeyraWallet.configure(
            .init(
                environment: .test,
                clientID: Self.clientID,
                clientSecret: Self.clientSecret,
                paymentAppProviderID: "WID-APP-001",
                tokenRequestorID: "50120834693",
                httpLoggingEnabled: true,
                appleTeamID: "TV4JRK677Z" // mandatory since STORY-36 slice 5 (sample app's team)
            )
        )
        // The sample identity's canonical wallet-proven tuple; any response_code proves the
        // round-trip (the assertion is on reaching the backend, not on approval).
        let response = try await VeyraWallet.shared.tokenisation.verifyAccount(
            accountNumber: "1000000192",
            institutionCode: "090325",
            walletAccountID: "michael@sparklemfb.ng",
            accountHolderName: "Michael Enoma"
        )
        XCTAssertNotNil(response.responseCode, "no response_code — did the call reach UAT?")
    }

    func testSoftposBanksReachesUatEndToEnd() async throws {
        VeyraSoftPOS.configure(
            .init(
                environment: .test,
                clientID: Self.clientID,
                clientSecret: Self.clientSecret,
                httpLoggingEnabled: true
            )
        )
        let banks = try await VeyraSoftPOS.shared.merchant.banks()
        XCTAssertFalse(banks.isEmpty, "UAT returned no settlement banks")
    }
}
