# Native Metanet Explorer handoff on iOS

New installations select Metanet Explorer and Crypton v2. Settings preserves the original portal and BRC-100 JSON choices; existing saved settings are not silently migrated.

## Request lifecycle

Crypton 2.4.1 keeps one local capability page open for each crypto, search, inbox or outbox operation. Individual wallet calls have fresh UUIDs and are validated natively before entering the queue. The page fetches each command at most once; a duplicate page or refresh cannot repeat a payment invocation. Wallet results never travel in URL schemes.

The server binds only to `127.0.0.1` on an ephemeral port and checks Host, Origin, content type, capability and UUID. The HTML loads only packaged scripts; framing and remote script execution are disallowed. The strict parser bounds HTTP connections, headers and bodies and rejects ambiguous requests.

Updated ME establishes the app pairing identity from a signed capability URL and a Keychain app key. Crypton’s Settings and ME’s grouped review show a matching code. Same-team clients may also use UIKit attribution; Apple withholds it across signing teams and in these ad-hoc simulator builds. A different pairing key cannot reuse existing grants. Its reviewed manifest declares six selectable protocol scopes under BRC-116; payments retain a separate review. Page-supplied originator claims cannot establish this identity. The native callback control accepts only the registered return capability and cannot leave an active wallet prompt.

An ordinary ME operation no longer needs a manual return after each call. On completion, the page requests the exact callback. During a long approval, iOS may suspend Crypton; after ME finishes, the page foregrounds Crypton and retries saving that same response. It does not invoke the wallet again. Older ME builds retain the manual app-switcher fallback.

Completed wallet pages make at most one accepted automatic return per command. Revealing an old page while ME navigates to a new capability does not trigger another app switch. An explicit tap on **Return to Crypton** remains available for recovery; a new wallet command starts a new return cycle.

Crypton keeps a successful operation pending until its wallet handoff has returned to the active app. This also applies to identity/readiness checks, so their completion cannot race the next operation. iOS may ask to **Open Crypton**; this navigation confirmation is separate from wallet permissions and Pay. The return wait allows up to five minutes and displays the required action. Networking still starts only after Crypton is active. Cancellation and failed wallet calls do not automatically repeat a signature, HMAC, payment or submission.

## Cancellation and iOS limits

ME approval calls have a five-minute deadline; enclosing engine/authentication exchanges have a fifteen-minute budget. Native HTTP calls retain independent network deadlines and response limits. Background tasks are finite; background audio is never used to keep the bridge running. Device locking can make protected journals unavailable until unlock.

The outbox records payment intent before the wallet receives `createAction`. Cancellation, timeout and a lost response preserve the recovery record. Fresh empty history alone cannot authorize another payment. The companion ME update can report a definite denial from a pre-commit permission check; only that evidence plus an empty, recent history from the original wallet exposes **Retry declined payment**. See [the detailed change and verification report](WALLET_USABILITY_2_4_1.md).

## Compatibility evidence

The actual local Metanet Explorer source confirms the `metanet` iOS URL scheme and `browser?url=` route in `app.json`, `ios/Metanet/Info.plist` and `hooks/useDeepLinking.ts`. The browser uses the ReactNativeWebView CWI transport in `utils/webview/walletBridge.ts` and derives its originator from the native frame URL in `walletBridgeProtocol.ts`. The companion ME change adds native-app attribution, grouped declarations, persistence ordering and guarded return handling.

Tests run the shipped page in a real WKWebView, transport requests to an independent SDK wallet, return through the callback route, and exercise normal crypto, denial, native MessageBox payment and delivery recovery. This harness validates the Crypton implementation and the observed protocol contract; it is not an installed ME app with a live user profile.

## Verification scope

The operator requested emulator-only verification. Automated tests use the dedicated Crypton iOS simulator, ad-hoc signing, a real share extension, and disposable SDK/MessageBox fixtures. Those fixtures use no live account permissions, production transactions or real funds. No physical device was used.

The simulator suite exercises the native request page, its local server, both foreground-return paths, permission denial, crypto operations, actual share-extension text/QR imports and payment/delivery recovery through an independent SDK backend. A harness supplies the observed ME CWI transport; no real account permissions or payment approvals are automated.

Separate live emulator checks on 30 October 2026 used the installed iOS and Android ME wallets and production MessageBox in both directions. Messaging permissions and payment totals were reviewed before sending. After a lost iOS wallet response, recovery found the labelled transaction, retrieved its confirmed proof and resumed delivery using the existing payment. Each receiving ME wallet displayed its notification, and Crypton decrypted the exact test plaintext. Legacy installed-wallet messages also passed in both directions.

See [the verification report](PORT_VERIFICATION.md) and [remaining-functions QA](REMAINING_FUNCTIONS_QA.md). Wallet-specific receipts and raw local experiments are excluded from publication. The automated fixtures never broadcast transactions or spend real funds.
