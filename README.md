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

## Connecting to Veyra

From **SDK 3.0.0** you pass **one provider** to `configure`, and it says how the SDK reaches the
Veyra backend. The same provider serves both SDKs. There is **no default**: which kind you
implement is your decision as the payment app provider. `VeyraProvider`, `VeyraProviderType`,
`VeyraAssertionProvider`, `VeyraProxyProvider` and `VeyraRelayError` come with `import VeyraWallet` /
`import VeyraSoftPOS`.

| Provider | `providerType` | The SDK… | Choose it when |
|---|---|---|---|
| `VeyraAssertionProvider` | `.authentication` | calls Veyra itself, with a token it obtains by exchanging a short-lived **assertion your backend signs** for the signed-in user | your backend can sign a JWT for the logged-in user (recommended) |
| `VeyraProxyProvider` | `.proxy` | calls **nothing** itself: every call is handed to your provider, which forwards it through **your backend** | you want all traffic through your own backend, or cannot run a signer |

**The protocol you conform to is the method.** Each protocol supplies its `providerType` by
default, so you never set a mode. Rules that hold for every provider:

- **One provider for both SDKs.** `VeyraSDK.configure` passes it to both; a standalone app passes
  it to the one SDK it uses. Each SDK still keeps its own token cache and device key.
- **`configure` throws** `.invalidConfiguration(message:)`, naming the problem, for a type that
  conforms to more than one kind, a `providerType` that contradicts its protocol, or a blank
  `clientId` — never at the first payment.
- **One kind per process, with no fallback.** A `VeyraAssertionProvider` whose `assertion` returns `nil`
  ends the call with reason `NOT_AUTHENTICATED` (`NOT_SENT` on a payment or digitise, `FAILED` on
  any other call); the SDK never tries another method. Configuring again with the other kind throws
  `.invalidConfiguration`.
- **Every `configure` re-binds the provider** — the one you pass is the one the SDK uses from then
  on, including from its own background work.
- **A call is never sent without credentials.** When the SDK cannot obtain a token, the call ends
  with reason `NOT_AUTHENTICATED` — `NOT_SENT` on a payment or digitise, `FAILED` on any other
  call — and nothing is sent.
- Every backend call (token requests included) carries `X-Veyra-Sdk-Version` and
  `X-Veyra-Provider-Type` (your provider's `providerType`: `AUTHENTICATION` or `PROXY`).

```swift
// (customerID:, config:, provider:) — the same order as Android and React Native.
let sdk = try VeyraSDK.configure(
    customerID: customerID,
    config: VeyraSDKConfiguration(
        softpos: .init(environment: .live, paymentAppProviderID: providerID),
        wallet: .init(environment: .live, paymentAppProviderID: providerID,
                      tokenRequestorID: requestorID, appleTeamID: teamID)),
    provider: MyAssertionProvider(bank: bankAPI))          // or MyProxyProvider(bank: bankAPI)
let wallet = try sdk.wallet       // VeyraWallet.shared
let softpos = try sdk.softpos     // VeyraSoftPOS.shared
```

**Upgrading from 3.0.0 (setup):** every `configure` takes `(customerID:, config:, provider:)`:
`VeyraWallet.configure(customerID:config:provider:)`, `VeyraSoftPOS.configure(customerID:config:provider:)`
and `VeyraSDK.configure(customerID:config:provider:)` with a `VeyraSDKConfiguration(softpos:wallet:)`.
Each returns its instance. `VeyraSDK.shared.wallet` / `.softpos` give the member SDKs, and
`currentMode` is now a method, `currentMode()`.

### `VeyraAssertionProvider` (recommended)

```swift
struct MyAssertionProvider: VeyraAssertionProvider {
    let clientId = "<your client id>"                  // public, issued at onboarding
    let bank: MyBankAPI

    func assertion(audience: String, jkt: String) async throws -> String? {
        try await bank.sdkAssertion(audience: audience, jkt: jkt)   // POST {your backend}/sdk-assertion — JWT or nil
    }
}
```

The provider is called only when the SDK holds no valid token (first call, expiry, or a token the
server refused), never more than once at a time. `jkt` is the thumbprint of this install's
proof-of-possession key. Return the signed assertion, or `nil` when no user is signed in;
returning `nil` or throwing fails the call with `.notAuthenticated` and sends nothing.

`audience` is the base URL of the Veyra API the SDK will redeem the assertion at
(`https://api.uat.veyra.co` on `TEST`, `https://api.veyra.co` on `LIVE`). **Check it before you
sign:** copy it into `aud` only when it is a Veyra base URL you expect for that environment, and
refuse anything else, so an assertion your backend signs can never be redeemed anywhere but Veyra.

**What your backend signs** — a compact JWT, with the signing key held in an HSM or KMS:

**Required by Veyra — the minimum.** How you produce the assertion is up to you: your own
endpoint, your authorization server's token exchange (RFC 8693), or any identity provider. Veyra
checks only the following. An assertion that is missing any of them, or fails a check, is refused,
and the SDK reports `NOT_AUTHENTICATED`.

| Part | What to put in it | Why Veyra needs it |
|---|---|---|
| Signature (`alg`) | `ES256`, `ES384`, `PS256` or `RS256` (the ones agreed for your issuer), signed with a private key held in an HSM or KMS. Never `none` or an HMAC (`HS…`) algorithm | Veyra verifies it with your **public** key (your JWKS URI, or keys you registered). That proves the assertion came from you, and Veyra can never create one itself |
| `kid` (header) | The id of the signing key in your JWKS. It can be left out only if you publish exactly one key | Picks the key to verify with, so you can rotate: publish the new key, then start signing with it |
| `iss` | Exactly the issuer identifier registered with Veyra, character for character | Tells Veyra whose keys and rules apply. An unknown or disabled issuer is refused |
| `sub` | A stable, pairwise identifier for the signed-in user: the same value every time for that user. Never an account number, customer id, phone number or email | Veyra derives its own user id from `iss` + `sub`, so the same person is recognised across sessions and devices without you sharing who they are |
| `aud` | The `audience` the SDK passed to your provider (the Veyra API base URL: `https://api.uat.veyra.co` on `TEST`, `https://api.veyra.co` on `LIVE`), or the alias agreed at onboarding | Addresses the assertion to Veyra only, so no other service that trusts your key can accept it |
| `iat` | When you issued it, in seconds since the epoch | Must not be in the future (Veyra allows 60 seconds of clock difference). Together with `exp`, it bounds the assertion's life |
| `exp` | The expiry: at most your agreed maximum after `iat`, which is **5 minutes** unless agreed otherwise | Limits how long a leaked assertion could be used. An expired one is refused |
| `jti` | A new unique id for every assertion, e.g. a UUID | Veyra accepts each `iss` + `jti` only once, so a captured assertion can't be replayed |

**Optional:**

| Claim | What to put in it | Why |
|---|---|---|
| `cnf.jkt` *(recommended)* | Exactly the `jkt` the SDK passed to your provider | Binds the assertion to this device's key. If it's present, Veyra refuses the assertion unless it matches the key the SDK proves it holds, so a leaked assertion is useless on any other device. Veyra can make it mandatory for your issuer if you agree to that |
| `acr` | The authentication level of the user's session, from the values agreed at onboarding | Needed only if Veyra sets a minimum level for your issuer, e.g. to require multi-factor sign-in. Below the minimum, the assertion is refused |
| `nbf` | A not-before time | Honoured if present |

**Only the required claims above are mandatory.** `cnf.jkt`, `acr` and `nbf` are optional: include
`acr` only if Veyra has agreed a minimum sign-in level for your issuer. Any other claim is ignored.

**Device binding between your app and your backend is optional.** You don't have to bind the
assertion to the device, either with `cnf.jkt` or by using DPoP on your own `/sdk-assertion`
endpoint. Veyra accepts an unbound assertion that meets the minimum above. Either way, the SDK
always uses DPoP with Veyra: the access token it gets is bound to a key generated on this device
that cannot be exported. **What binding adds:** without it, an assertion that leaks in its few
minutes of life could be redeemed once by another device. With it, it can't be redeemed anywhere
else.

The access token is bound to a key generated on this device that cannot be exported (Secure
Enclave). Nothing more is needed from your app; `signOut()` drops cached tokens but keeps the
per-install key.

A reference endpoint (your backend, authenticated with your app's own session):

```
POST {your backend}/sdk-assertion
     {"audience": "<audience>", "jkt": "<jkt>"}
  →  200 {"assertion": "<compact JWT>"}     401 when no user is signed in (return nil)
```

### `VeyraProxyProvider`

```swift
struct MyProxyProvider: VeyraProxyProvider {
    let bank: MyBankAPI

    func send(_ request: String) async throws -> String {
        // POST {your API gateway}/issuertokengateway/v1/proxy with `request` as the body; return the body.
        // On failure throw VeyraRelayError(kind:neverSent:httpStatus:) — see below.
    }
}
```

**The request envelope (version 1) is public API.** Each `request` is one JSON string that says
everything about the call:

```json
{ "version": 1,
  "service": "SOFTPOS",
  "method": "POST",
  "path": "/payment",
  "query": { "merchant_id": "…" },
  "headers": { "Content-Type": "application/json",
               "X-Veyra-Sdk-Version": "3.0.0",
               "X-Veyra-Provider-Type": "PROXY" },
  "body": "<the request JSON, as a string>" }
```

- `service` is the Veyra API the call is for: `WALLET` or `SOFTPOS`. It names the API, not your
  SDK — a wallet call to the payment API is `SOFTPOS`. Your proxy backend routes on it.
- `method` is the HTTP method to use towards Veyra. Because the envelope names it, the provider has a
  single `send` and every call goes to one endpoint.
- `path` is relative to that service — never a full URL, and without any API prefix.
- `query` is omitted when there is none (values are decoded). `body` is absent on `GET` and `DELETE`.
- New fields may be added under the same `version`; a breaking change bumps `version`.

**The response:** return Veyra's response body exactly as Veyra returned it. If Veyra answered with
a non-200 status, throw `VeyraRelayError(kind: .other, neverSent: false, httpStatus: status)`
rather than inventing a body — the SDK treats it exactly as that status on a direct connection.

**Failures must say whether the request was sent.** Throw `VeyraRelayError(kind:neverSent:httpStatus:)`:

- `neverSent: true` **only** when the request provably never left the device (no network, the
  connection was refused before anything was written). The call then ends with reason
  `SDK_UNABLE_TO_CONNECT`, or `NO_NETWORK_CONNECTION` when the kind is `.noNetwork` — `NOT_SENT`
  on a payment or digitise, `FAILED` on any other call.
- `neverSent: false` when it may have been delivered — a timeout, a lost connection, or when you
  cannot tell. The payment stays `PENDING` and the SDK reconciles it.
- **Any other error** counts as `neverSent: false`, and so does a call that outlives the
  SDK's own timeout.

A reference endpoint:

```
POST {your API gateway}/issuertokengateway/v1/proxy
     body: the envelope, unchanged
  →  your gateway checks the app's session, removes the `/issuertokengateway/v1` context and
     forwards the envelope to your issuer token gateway (ITG) as `POST /proxy`.
     The ITG authenticates to Veyra with its own OAuth client-credentials token
     (an API key is not accepted), calls `service` + `path` with `method`, `query`, `headers`
     and `body`, and answers with Veyra's status and body unchanged.
```

When the proxy backend itself cannot complete a call it answers `200` with
`{"response_status": "PROXY_FAILED", "response_status_reason": "…", "never_sent": true|false}`.
Return that body unchanged like any other — the SDK recognises it and treats the call as not sent
(`never_sent: true`) or possibly delivered (anything else).

**Your proxy provider is called from background work too** — status polling, payment-key refresh and
credit confirmations run on the SDK's app-scoped loops — so it must not depend on a screen being
up. Before your app has configured the SDK there is no provider, and those cycles skip without failing.

**What your backend can see.** Request and response bodies pass through your app and backend. Key
material is end-to-end encrypted to the device and payment proofs are MACed, so your backend cannot
read or forge either; it **can** read account and identity fields, and it could alter plain
answers such as a transaction status. That is acceptable only because you, the provider, already
hold that data. **Forward the bytes unmodified.** The SDK's log export does not go through
your provider.

## Outcomes

Every call that performs an operation answers with an **outcome**, never a thrown failure:
`responseStatus`, `responseStatusReason` (what to show and log), and `responseCode` on payments
(for receipts and support — never branch on it). `ResponseStatus` has the constants.

| `responseStatus` | Meaning | Your reference (merchant order ID) | What to do |
|---|---|---|---|
| `APPROVED` | done | used — paid | complete |
| `DECLINED` | done; someone with authority refused; no money moved | free | show `responseStatusReason`; another card or method may be tried under the **same** order ID |
| `FAILED` | it was not performed, and retrying with the same reference won't help — on a call other than a payment or digitise, also when it never reached Veyra (no network, not authenticated, …) | free, except after `94` (the order is already paid or possibly paid) | fix the reason and try again |
| `PENDING` | it may have been done; not known yet | used | **never retry** — the SDK keeps checking and tells you when it settles |
| `RETRY` | it reached Veyra, but was never sent to the bank; nothing was done | **unused** | fix the reason; retry with the **same** order ID |
| `NOT_SENT` | payments and digitise only: it never reached Veyra; nothing was done | **unused** | fix the reason (connect, authenticate, …); retry with the **same** order ID (or digitise request) |

`RETRY` and `NOT_SENT` are handled the same way — nothing was debited, so retry with the **same**
order ID; `responseStatusReason` says where it stopped. `RETRY` is Veyra's answer (it carries a
`responseCode` and is recorded in history); `NOT_SENT` never left the phone and carries no code.
An order ID can be used again until the order is `APPROVED` or `PENDING`; after that a new attempt
answers `94` / `FAILED` / `DUPLICATE_MERCHANT_ORDER_ID`.

**`NOT_SENT` is only for payments and digitise** — the merchant card tap, the customer-QR charge,
creating a merchant-presented QR, scan-to-pay, show-QR-to-pay and digitise, where it tells you the
reference is still unused. Every other call (merchant registration, activation, status and bank
lists, wallet banks, account verification, activation codes, token status, card removal,
customer-QR inspection, receipt scan, card selection) answers **`FAILED`** with the same reason
(`NO_NETWORK_CONNECTION`, `SDK_UNABLE_TO_CONNECT`, `NOT_AUTHENTICATED`, `INVALID_REQUEST`, …): fix
the reason and call again.

Three wallet calls also answer rather than throw: `processReceipt` (checked on the phone) answers a
`ReceiptScan` (`APPROVED` with the stored receipt, or `FAILED` with `INVALID_RECEIPT`,
`RECEIPT_NOT_FROM_THIS_WALLET`, `RECEIPT_MISMATCH`, `PAYMENT_NOT_CONFIRMED` or
`RECEIPT_FOR_ANOTHER_TRANSACTION`); `setActiveToken` (on the phone) answers a `CardSelection`
(`APPROVED`, or `FAILED` / `CARD_NOT_FOUND`); `reconcilePendingTransactions` is a read and answers a
`ReconcileResult` whose `failureReason` is set only when the reconcile could not run.

Reads that check a payment (`refreshTransactionStatus`, `transactions.status`, `contextStatus`…)
return `VeyraLookup` — the value, or a `failureReason` when the check could not be made — and never
change the stored row on failure. The only thing that throws is a setup error — a mistake in your
integration: `.notConfigured`, `.notSignedIn`, `.invalidConfiguration(message:)`, `.sessionRequired`,
`.unsupportedOnPlatform`. The full list of reasons is in the developer guide.

## Cancelling a payment or adding a card

A payment or an add-card can be cancelled only while its request is still on the phone. Every cancel
names the call by a reference you already hold, answers at once with a `CancelResult`, and never
throws:

```swift
// Merchant: a card tap, a customer-QR charge or a payment-QR create — one call for all three.
let tapAnswer = VeyraSoftPOS.shared.payments.cancelPayment(merchantOrderID: orderID)

// Wallet: scan-to-pay, by the order ID in the scanned QR.
let wallet = VeyraWallet.shared
let payAnswer = wallet.cancelPayment(merchantOrderID: verified.merchantOrderID ?? "")

// Wallet: add a card — start it with your own ID, cancel with the same one.
let result = try await wallet.digitise(DigitiseParams(/* … */, clientRequestID: requestID))
let addCardAnswer = wallet.cancelDigitise(clientRequestID: requestID)
```

| `CancelResult` | What happened | What to show |
|---|---|---|
| `.cancelled` | Nothing was sent. The call itself ends `NOT_SENT` / `CANCELLED` (a tap through its `.result` event). | Go back to the previous screen. Retry with the **same** reference. |
| `.tooLateToCancelRequestAlreadySent` | The request has already left the phone. The call carries on and delivers its normal result. | "This can no longer be cancelled" — keep waiting for the result. |
| `.noPaymentInProgressForOrderID` / `.noDigitisationInProgressForClientRequestID` | Nothing with that reference was in progress (wrong reference, never started, or already finished). | Nothing to cancel. |

The answer is the reply to the cancel, never the call's status: always take the outcome from the call
itself. A card tap can still be cancelled after the customer's card has been read, up to the moment the
payment is sent; the card data is then discarded. Show-QR-to-pay has nothing to cancel on the wallet —
the merchant's charge is the payment. Cancelling the Swift `Task` that awaits `digitise`,
`payScannedContext`, `chargeCustomerQr` or `createContext` cancels the call the same way, without an
answer: before sending it returns `NOT_SENT` / `CANCELLED`, after sending it returns its normal result.

**Migrating:** `TapPaymentSession.cancel()` is removed. Call
`VeyraSoftPOS.shared.payments.cancelPayment(merchantOrderID:)` with the sale's order ID instead —
including when the waiting screen leaves. Unlike the old call, it never stops a payment that is
already with the bank.

## Looking up a payment by your order ID

`VeyraSoftPOS.shared.transactions.paymentStatus(merchantOrderID:)` answers "what happened to this
order?" for every SoftPOS rail — `tap.session`, `payments.createContext` and
`payments.chargeCustomerQr` — without saying which. Use it for a payment that ended `PENDING`, or
when your app restarted before the result arrived. It returns `VeyraLookup<OrderPaymentStatus>`:
`responseStatus` is the **order's** status, by precedence over all its attempts — any `APPROVED`,
else any `PENDING`, else the latest attempt (`DECLINED`, `FAILED` or `RETRY`); an order with no
attempts (including a merchant QR not paid yet) is `RETRY` / `25` / `UNABLE_TO_LOCATE_RECORD`. It
also carries the deciding attempt's code, reason, `reference`, `transactionID` and
`amountMinorUnits`, every attempt newest first, and `answeredBy` (`DEVICE` when this phone's own
record is final, otherwise `GATEWAY`). A payment still on its way counts: it is on the history as `PENDING` before its request leaves, so mid-flight the lookup answers `PENDING`, even before the gateway has a record of it. It is a read: only a setup error throws — when the gateway
could not be asked, `failureReason` says why and `value` is what this phone holds, if anything. A blank order ID answers `INVALID_REQUEST`, a device with no registered merchant
`MISSING_MANDATORY_CONFIG`. The wallet has no lookup by order ID.

**The retry rule.** After `NOT_SENT`, `RETRY`, `DECLINED` or `FAILED` no money moved: keep the
order ID and pay again under the **same** one. After `APPROVED` or `PENDING` (or a status your build
doesn't know — treat it as pending) the order is paid or may be: a new payment for it is refused
`94` / `FAILED` / `DUPLICATE_MERCHANT_ORDER_ID` with `originalPayment`, so don't take another
payment.

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
