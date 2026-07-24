// Stored-merchant persistence (ISSUE-05): a successful registration must survive app
// restarts. Covers the registration fold, the isRegistered criteria, the facade
// read/clear paths over an injected in-memory store, the status/update folds (including
// the different-merchant guard), and a Keychain round-trip. Network verticals stay with
// the KMP commonTests / the sample app, as for the rest of the facade.
import Security
import XCTest
@testable import VeyraSoftPOS

private final class InMemoryMerchantStorage: MerchantStorage {
    var merchant: StoredMerchant?
    func load() -> StoredMerchant? { merchant }
    func save(_ merchant: StoredMerchant) { self.merchant = merchant }
    func clear() { merchant = nil }
}

final class VeyraSoftPOSStoredMerchantTests: XCTestCase {

    private var storage: InMemoryMerchantStorage!

    override func setUp() {
        super.setUp()
        storage = InMemoryMerchantStorage()
        VeyraSoftPOS.shared.replaceMerchantStorage(storage)
    }

    override func tearDown() {
        VeyraSoftPOS.shared.replaceMerchantStorage(KeychainMerchantStorage())
        super.tearDown()
    }

    private func registration(bvn: String? = "22170281458") -> MerchantRegistration {
        MerchantRegistration(
            merchantType: .personal, merchantName: "Ada", emailAddress: "a@x.co", phoneNumber: "080",
            addressLine1: "1 St", city: "Lagos", state: "LA", countryCode: "0566",
            bvn: bvn, accountNumber: "0123456789", institutionCode: "120001", acquirerID: "ACQ"
        )
    }

    private func stored(
        merchantID: String = "M1",
        merchantCategoryCode: String = "5411",
        terminalID: String = "T1",
        merchantStatus: String? = "PENDING"
    ) -> StoredMerchant {
        StoredMerchant(
            registration: registration(),
            merchantID: merchantID,
            terminalID: terminalID,
            merchantStatus: merchantStatus,
            merchantCategoryCode: merchantCategoryCode,
            countryCode: nil,
            acquirerID: nil
        )
    }

    // MARK: Registration fold

    func testFoldPrefersResponseAssignedValues() {
        let merchant = StoredMerchant(
            registration: registration(),
            merchantID: "M1",
            terminalID: "T9",
            merchantStatus: "ACTIVE",
            merchantCategoryCode: "5411",
            countryCode: "0999",
            acquirerID: "ACQ-RESP"
        )
        XCTAssertEqual(merchant.merchantID, "M1")
        XCTAssertEqual(merchant.terminalID, "T9")
        XCTAssertEqual(merchant.merchantStatus, "ACTIVE")
        XCTAssertEqual(merchant.merchantCategoryCode, "5411")
        XCTAssertEqual(merchant.countryCode, "0999")
        XCTAssertEqual(merchant.acquirerID, "ACQ-RESP")
        // Submitted identity carried over.
        XCTAssertEqual(merchant.merchantType, "PERSONAL")
        XCTAssertEqual(merchant.merchantName, "Ada")
        XCTAssertEqual(merchant.bvn, "22170281458")
        XCTAssertNil(merchant.cacNumber)
    }

    func testFoldFallsBackToSubmittedValues() {
        let merchant = StoredMerchant(
            registration: registration(),
            merchantID: "M1",
            terminalID: nil,
            merchantStatus: nil,
            merchantCategoryCode: nil,
            countryCode: nil,
            acquirerID: nil
        )
        XCTAssertEqual(merchant.terminalID, "M1", "terminal ID falls back to the merchant ID")
        XCTAssertEqual(merchant.countryCode, "0566")
        XCTAssertEqual(merchant.acquirerID, "ACQ")
        XCTAssertEqual(merchant.merchantCategoryCode, "")
        XCTAssertNil(merchant.merchantStatus)
    }

    // MARK: isRegistered criteria (mirrors Android MerchantService.isRegistered)

    func testIsRegisteredFalseWithNothingStored() {
        XCTAssertNil(VeyraSoftPOS.shared.merchant.stored)
        XCTAssertFalse(VeyraSoftPOS.shared.merchant.isRegistered)
    }

    func testIsRegisteredTrueOnlyWithAllTransactionRequiredFields() {
        storage.save(stored())
        XCTAssertTrue(VeyraSoftPOS.shared.merchant.isRegistered)

        // A merchant without a backend-assigned MCC is stored but not transaction-ready.
        storage.save(stored(merchantCategoryCode: ""))
        XCTAssertNotNil(VeyraSoftPOS.shared.merchant.stored)
        XCTAssertFalse(VeyraSoftPOS.shared.merchant.isRegistered)
    }

    // MARK: Facade read / clear

    func testStoredAndClearStoredRoundTrip() {
        let merchant = stored()
        storage.save(merchant)
        XCTAssertEqual(VeyraSoftPOS.shared.merchant.stored, merchant)

        VeyraSoftPOS.shared.merchant.clearStored()
        XCTAssertNil(VeyraSoftPOS.shared.merchant.stored)
        XCTAssertFalse(VeyraSoftPOS.shared.merchant.isRegistered)
    }

    // MARK: Status refresh fold

    func testStatusUpdateOnlyTouchesTheStoredMerchant() {
        storage.save(stored(merchantID: "M1", merchantStatus: "PENDING"))

        VeyraSoftPOS.shared.updateStoredMerchantStatus(merchantID: "OTHER", status: "ACTIVE")
        XCTAssertEqual(storage.merchant?.merchantStatus, "PENDING")

        VeyraSoftPOS.shared.updateStoredMerchantStatus(merchantID: "M1", status: "ACTIVE")
        XCTAssertEqual(storage.merchant?.merchantStatus, "ACTIVE")
    }

    func testStatusUpdateWithNilKeepsExistingStatus() {
        storage.save(stored(merchantID: "M1", merchantStatus: "ACTIVE"))
        VeyraSoftPOS.shared.updateStoredMerchantStatus(merchantID: "M1", status: nil)
        XCTAssertEqual(storage.merchant?.merchantStatus, "ACTIVE")
    }

    // MARK: Profile-update fold

    func testApplyUpdatePreservesBackendAssignedFields() {
        storage.save(stored(merchantID: "M1", merchantCategoryCode: "5411", terminalID: "T1"))
        let update = MerchantUpdate(
            merchantName: "Ada Ltd", emailAddress: "new@x.co", phoneNumber: "081",
            addressLine1: "2 Ave", city: "Abuja", state: "FC", countryCode: "0566",
            accountNumber: "9999999999", institutionCode: "120002", acquirerID: "ACQ"
        )

        VeyraSoftPOS.shared.applyStoredMerchantUpdate(merchantID: "M1", update: update, status: "ACTIVE")

        let merchant = storage.merchant
        XCTAssertEqual(merchant?.merchantName, "Ada Ltd")
        XCTAssertEqual(merchant?.accountNumber, "9999999999")
        XCTAssertEqual(merchant?.merchantStatus, "ACTIVE")
        XCTAssertEqual(merchant?.terminalID, "T1", "backend-assigned fields are preserved")
        XCTAssertEqual(merchant?.merchantCategoryCode, "5411", "backend-assigned fields are preserved")
        XCTAssertEqual(merchant?.bvn, "22170281458", "type-specific identity is preserved")
    }

    func testApplyUpdateForDifferentMerchantIsIgnored() {
        let before = stored(merchantID: "M1")
        storage.save(before)
        let update = MerchantUpdate(
            merchantName: "X", emailAddress: "x@x.co", phoneNumber: "1",
            addressLine1: "1", city: "L", state: "L", countryCode: "0566",
            accountNumber: "1", institutionCode: "1", acquirerID: "A"
        )

        VeyraSoftPOS.shared.applyStoredMerchantUpdate(merchantID: "OTHER", update: update, status: "ACTIVE")

        XCTAssertEqual(storage.merchant, before)
    }

    // MARK: Keychain round-trip (simulator/device keychain)

    func testKeychainStorageRoundTrip() throws {
        // The bare xctest runner has no keychain entitlement (errSecMissingEntitlement) —
        // the round-trip only runs app-hosted; the sample app covers it otherwise.
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "co.veyra.softpos.test-probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("x".utf8),
        ]
        let probeStatus = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        try XCTSkipIf(
            probeStatus != errSecSuccess && probeStatus != errSecDuplicateItem,
            "Keychain unavailable in this test runner (OSStatus \(probeStatus))"
        )

        let keychain = KeychainMerchantStorage()
        keychain.clear()
        defer { keychain.clear() }
        XCTAssertNil(keychain.load())

        let merchant = stored()
        keychain.save(merchant)
        XCTAssertEqual(keychain.load(), merchant)

        // Overwrite (SecItemUpdate path), not duplicate.
        let updated = merchant.updatingStatus("ACTIVE")
        keychain.save(updated)
        XCTAssertEqual(keychain.load(), updated)

        keychain.clear()
        XCTAssertNil(keychain.load())
    }
}
