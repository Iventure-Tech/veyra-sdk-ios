# Veyra SDK for iOS

The Veyra SDK turns a phone into either side of a contactless payment:

- **SoftPOS (merchant side)** — accept payments: NFC tap acceptance, get-paid QR codes,
  scanning customer payment QRs, merchant registration, transaction history and receipts.
- **Wallet (customer side)** — make payments: account tokenisation ("add card"), token
  activation, scan-to-pay, show-QR-to-pay, transaction history and receipts.

| Integration | iOS product | Use when |
|---|---|---|
| **SoftPOS only** | `VeyraSoftPOS` | Your app only accepts payments |
| **Wallet only** | `VeyraWallet` | Your app only makes payments |
| **Combined** | `VeyraSDK` | One app does both — never at the same time; the SDK enforces an exclusive mode |

> Tap-to-**pay** (card emulation) is not available on iOS — Apple restricts card emulation —
> so the iOS wallet pays by QR (scan-to-pay and show-QR-to-pay). Tap **acceptance** works on
> NFC-capable iPhones.

## Getting the SDK

Add the package in Xcode (**File → Add Package Dependencies…**) or in your `Package.swift`:

```
https://github.com/Iventure-Tech/veyra-sdk-ios
```

Pin an exact released version, then add the products your integration needs
(`VeyraSDK`, `VeyraSoftPOS`, `VeyraWallet`).

The package's precompiled binary is hosted on the Veyra artifact server, which is
authenticated — put the repository credentials from your Veyra onboarding in `~/.netrc`
(`machine repo.veyra.co` + login/password, `chmod 600`) so SwiftPM can download it.

## Documentation & sample app

The full **iOS developer guide** — platform requirements (Info.plist keys, entitlements,
App Attest prerequisites), the complete public API reference with async/closure samples for
every capability, and the error catalogue with per-outcome guidance — lives with the public
sample app:

**https://github.com/Iventure-Tech/veyra-ios-sample-app**

The sample is a complete working integration (merchant and wallet, every rail) built
against this package — clone it, add your onboarding credentials, and run.

Building for **Android**? The artifacts publish to the Veyra Maven repository and the
Android sample + guide live at https://github.com/Iventure-Tech/veyra-android-sample-app.
