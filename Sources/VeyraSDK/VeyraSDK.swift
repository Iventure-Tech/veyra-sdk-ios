// VeyraSDK — public iOS API of the combined Veyra SDK.
//
// Pure-Swift facade over the VeyraKMP umbrella framework. Mirrors Android's `VeyraSdk`
// facade: a combined SoftPOS+Wallet app configures BOTH SDKs through this entry point,
// which also owns the app's **exclusive mode** — the same shared state machine that
// Android's mode handling delegates to:
//
// - the process starts (and re-configures to) **inert `.none`** — never live at launch, even
// after being killed in Pay;
// - mode derives from the foreground screen: screens call `activate(_:)` on appear and
// `release(_:)` on disappear (the iOS equivalent of Android's lifecycle observers);
// - switching away from a mode whose payment is mid-flight throws `VeyraSDKError.modeSwitchRefused`;
// - iOS has no HCE (Apple platform lock), so no capability toggling happens today; CoreNFC
// reader arming will consult the same arbiter.
//
// Android ↔ iOS name mapping (excerpt; full table in the package README):
// VeyraSdk.initialize(activity, config); VeyraSdk.setMode(NfcMode.WALLET)
// ↔ VeyraSDK.configure(...); try VeyraSDK.shared.setMode(.wallet)
import Foundation
import VeyraKMP
import VeyraSoftPOS
import VeyraWallet

/// The exclusive operating mode of a combined Veyra app (mirrors Android's `NfcMode`).
public enum VeyraMode: String, Sendable {
    /// No payment capability active. Safe idle default.
    case none = "NONE"
    /// Accepting payments (Get paid).
    case softpos = "SOFTPOS"
    /// Making payments (Pay).
    case wallet = "WALLET"
}

/// Errors thrown by the combined Veyra SDK.
public enum VeyraSDKError: Error, Sendable {
    /// `VeyraSDK.configure(_:)` has not been called.
    case notConfigured
    /// A mode switch was refused because the outgoing mode's payment is mid-flight.
    case modeSwitchRefused(message: String)
}

/// Entry point of the combined Veyra SDK on iOS (SoftPOS + Wallet + exclusive mode).
///
/// ```swift
/// VeyraSDK.configure(softpos: softposConfig, wallet: walletConfig)
/// // Get-paid screen:
/// .onAppear { VeyraSDK.shared.activate(.softpos) }
/// .onDisappear { VeyraSDK.shared.release(.softpos) }
/// ```
public final class VeyraSDK: @unchecked Sendable {

    public static let shared = VeyraSDK()

    private let lock = NSLock()
    private var configured = false

    private init() {}

    /// Configure the combined SDK: both member SDKs plus the exclusive-mode arbiter.
    /// The process starts **inert** (`.none`); safe to call again (reconfigures, stays inert).
    public static func configure(
        softpos: VeyraSoftPOSConfiguration,
        wallet: VeyraWalletConfiguration
    ) {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        VeyraSoftPOS.configure(softpos)
        VeyraWallet.configure(wallet)
        VeyraSdkKmp.shared.configure()
        shared.configured = true
    }

    private func requireConfigured() throws {
        lock.lock()
        defer { lock.unlock() }
        guard configured else { throw VeyraSDKError.notConfigured }
    }

    /// The app's current exclusive mode.
    public var currentMode: VeyraMode {
        lock.lock()
        defer { lock.unlock() }
        guard configured else { return .none }
        return VeyraMode(rawValue: VeyraSdkKmp.shared.currentMode()) ?? .none
    }

    /// Switch the exclusive mode explicitly.
    /// - Throws: `VeyraSDKError.modeSwitchRefused` while the outgoing mode's payment is mid-flight.
    public func setMode(_ mode: VeyraMode) throws {
        try requireConfigured()
        do {
            try VeyraSdkKmp.shared.setMode(modeName: mode.rawValue)
        } catch {
            throw VeyraSDKError.modeSwitchRefused(message: error.localizedDescription)
        }
    }

    /// A screen becoming active for `mode` (call on appear). Returns false when the switch is
    /// deferred because the other mode's payment is mid-flight.
    @discardableResult
    public func activate(_ mode: VeyraMode) -> Bool {
        guard (try? requireConfigured()) != nil else { return false }
        return VeyraSdkKmp.shared.activate(modeName: mode.rawValue)
    }

    /// A screen leaving `mode` (call on disappear): drops to `.none` if it was the active mode.
    public func release(_ mode: VeyraMode) {
        guard (try? requireConfigured()) != nil else { return }
        VeyraSdkKmp.shared.release(modeName: mode.rawValue)
    }
}
