// Umbrella mode-semantics tests (STORY-33 Phase 2): the Swift-visible contract of the shared
// ExclusiveModeCoordinator — inert at configure, mode from activate/release, cross-mode
// exclusivity. (Mid-flight refusal + capability ordering are pinned by the coordinator's
// commonTest on both platforms; Android's VeyraModeManagerTest guards the HCE side.)
import XCTest
import VeyraSDK
import VeyraSoftPOS
import VeyraWallet

// 'Z' prefix: XCTest runs suites alphabetically, and configuring the combined SDK here
// configures the process-global VeyraSoftPOS/VeyraWallet singletons — this suite must run
// AFTER their notConfigured tests (same trick as testZConfigure… inside those suites).
final class ZUmbrellaModeSemanticsTests: XCTestCase {

    private func configureCombined() {
        VeyraSDK.configure(
            softpos: .init(environment: .local, localBaseURLOverride: URL(string: "http://localhost:8083")!),
            wallet: .init(
                environment: .local,
                localBaseURLOverride: URL(string: "http://localhost:8080")!,
                appleTeamID: "TESTTEAMID" // mandatory since STORY-36 slice 5; no network touched
            )
        )
    }

    func testStartsInertAndSetModeSwitches() throws {
        configureCombined()
        XCTAssertEqual(.none, VeyraSDK.shared.currentMode, "must start inert (NONE) at configure")

        try VeyraSDK.shared.setMode(.wallet)
        XCTAssertEqual(.wallet, VeyraSDK.shared.currentMode)

        try VeyraSDK.shared.setMode(.none)
        XCTAssertEqual(.none, VeyraSDK.shared.currentMode)
    }

    func testActivateAndReleaseFollowTheForegroundScreenContract() {
        configureCombined()

        // Get-paid screen appears.
        XCTAssertTrue(VeyraSDK.shared.activate(.softpos))
        XCTAssertEqual(.softpos, VeyraSDK.shared.currentMode)

        // Pay screen takes over (exclusive: softpos gives way).
        XCTAssertTrue(VeyraSDK.shared.activate(.wallet))
        XCTAssertEqual(.wallet, VeyraSDK.shared.currentMode)

        // Releasing a mode that is not active is ignored.
        VeyraSDK.shared.release(.softpos)
        XCTAssertEqual(.wallet, VeyraSDK.shared.currentMode)

        // Pay screen disappears: inert again.
        VeyraSDK.shared.release(.wallet)
        XCTAssertEqual(.none, VeyraSDK.shared.currentMode)
    }

    func testReconfigureResetsToInert() throws {
        configureCombined()
        try VeyraSDK.shared.setMode(.softpos)
        // Re-configure (e.g. relaunch): must come back inert, never live.
        configureCombined()
        XCTAssertEqual(.none, VeyraSDK.shared.currentMode)
    }
}
