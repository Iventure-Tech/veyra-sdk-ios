# Veyra SDK for iOS

Swift package with three products — `VeyraSDK` (combined), `VeyraSoftPOS` (accept payments),
`VeyraWallet` (make payments) — built from the same codebase as the Veyra Android SDKs and
released in lockstep with them (one version train).

## Requirements

- iOS 15.0+
- Xcode 15+

## Installation (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…**, paste this repository's URL, and select
**Up to Next Major Version** from the latest release. Then add the product you need
(`VeyraSDK`, `VeyraSoftPOS`, or `VeyraWallet`) to your app target.

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "<this repository URL>", from: "1.0.0"),
]
```

The package wraps a precompiled binary (`VeyraKMP.xcframework`) that Xcode downloads and
checksum-verifies automatically during package resolution — no manual embedding needed.

## Documentation

The full developer guide — configuration, entitlements and Info.plist keys, the API
reference with samples, response codes and data models — is supplied with your SDK bundle
during onboarding.

## Note

This repository is the release distribution of the package: its contents (including
`Package.swift` and the version tags) are generated and published by the Veyra SDK release
pipeline. Issues and integration questions go through your Veyra onboarding contact, not
pull requests here.
