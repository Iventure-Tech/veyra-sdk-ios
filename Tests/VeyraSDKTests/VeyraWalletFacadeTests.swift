// First facade tests (STORY-33 Phase 2): the no-network paths of the VeyraWallet facade —
// unconfigured error, configuration, and the Swift-side Bank value semantics. Network verticals
// are exercised by the KMP commonTests (fake transport) and the sample app against LOCAL.
import XCTest
@testable import VeyraWallet

final class VeyraWalletFacadeTests: XCTestCase {

    func testBanksThrowsNotConfiguredBeforeConfigure() async {
        // NOTE: relies on running before any configure() in this process (fresh test runner).
        do {
            _ = try await VeyraWallet.shared.tokenisation.banks()
            XCTFail("expected notConfigured")
        } catch let error as VeyraWalletError {
            guard case .notConfigured = error else {
                return XCTFail("expected .notConfigured, got \(error)")
            }
        } catch {
            XCTFail("expected VeyraWalletError, got \(error)")
        }
    }

    func testConfigureWiresTheKmpSurface() throws {
        VeyraWallet.configure(
            .init(
                environment: .local,
                localBaseURLOverride: URL(string: "http://localhost:8080")!,
                appleTeamID: "TESTTEAMID" // mandatory since STORY-36 slice 5; no network touched
            )
        )
        // Configured: the guard no longer throws (no network is touched by configure itself).
        // A follow-up call would now attempt a real request, which is the sample app's job.
    }

    func testBankValueSemantics() {
        let a = Bank(slug: "gtb", name: "GTBank", institutionCode: "058152")
        let b = Bank(slug: "gtb", name: "GTBank", institutionCode: "058152")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, "058152")
    }

    func testStoredCardCarriesTheActiveFlag() {
        // STORY-42: the wallet's active token surfaces on the card record; identity stays the TUR.
        let card = StoredCard(
            tokenUniqueReference: "TUR-1", panLastFour: "1112",
            maskedPAN: "•••• •••• •••• 1112", expiry: "07/28",
            accountHolderName: "Michael Enoma", bankName: "Sparkle MFB",
            status: "APPROVED", requiresActivation: false, isActive: true
        )
        XCTAssertTrue(card.isActive)
        XCTAssertEqual(card.id, "TUR-1")
    }
}
