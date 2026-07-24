// SoftPOS facade tests (STORY-33 Phase 2): the no-network paths — unconfigured error,
// configuration, and Swift value semantics. Network verticals are covered by the KMP commonTests
// (fake transport) and the sample app against LOCAL.
import XCTest
import VeyraSoftPOS

final class VeyraSoftPOSFacadeTests: XCTestCase {

    func testMerchantStatusThrowsNotConfiguredBeforeConfigure() async {
        // NOTE: relies on running before any configure() in this process (fresh test runner).
        do {
            _ = try await VeyraSoftPOS.shared.merchant.status(merchantID: "M1")
            XCTFail("expected notConfigured")
        } catch let error as VeyraSoftPOSError {
            guard case .notConfigured = error else {
                return XCTFail("expected .notConfigured, got \(error)")
            }
        } catch {
            XCTFail("expected VeyraSoftPOSError, got \(error)")
        }
    }

    func testValueSemanticsAndDefaults() {
        let a = MerchantStatus(merchantID: "M1", status: "ACTIVE")
        let b = MerchantStatus(merchantID: "M1", status: "ACTIVE")
        XCTAssertEqual(a, b)

        let reg = MerchantRegistration(
            merchantType: .personal, merchantName: "Ada", emailAddress: "a@x.co", phoneNumber: "080",
            addressLine1: "1 St", city: "Lagos", state: "LA", countryCode: "NG",
            bvn: "12345678901", accountNumber: "0123456789", institutionCode: "120001", acquirerID: "ACQ"
        )
        XCTAssertEqual(reg.addressLine2, "")
        XCTAssertNil(reg.cacNumber)
        XCTAssertEqual(reg.merchantType.rawValue, "PERSONAL")
    }

    func testZConfigureWiresTheKmpSurface() {
        // 'Z' prefix: keep this after the notConfigured test (XCTest runs alphabetically).
        VeyraSoftPOS.configure(
            .init(environment: .local, localBaseURLOverride: URL(string: "http://localhost:8083")!)
        )
    }
}
