# Native Metanet Explorer handoff on iOS

New installations select Metanet Explorer and Crypton v2. Settings preserves the original portal and BRC-100 JSON choices; existing saved settings are not silently migrated.

## Request lifecycle

1. Crypton validates the wallet operation. For MessageBox, the native outbox validates the reviewed fee and records `PAYMENT_REQUESTED` before the wallet can receive `createAction`.
2. A listener binds only to `127.0.0.1` on an ephemeral port. A new 256-bit capability and request UUID are generated. A short iOS background task permits the handoff while Crypton is behind ME.
3. Crypton opens `metanet://browser?url=<encoded loopback page>`. The page polls its capability-scoped `next` route and forwards the command through `window.ReactNativeWebView.postMessage` using the official CWI invocation shape.
4. The page accepts only a matching response UUID and posts it to the exact local Origin. Native code checks Host, capability, method, content type, Origin, UUID and the strict Boolean `isInvocation: false` before accepting it. Duplicate and stale replies are rejected.
5. **Return to Crypton** carries only the capability. Some installed ME builds restrict external custom schemes; switching back with the iOS app switcher is also supported and completes the same already-received response. The result remains in memory. Foreground return completes the request, invalidates the capability and closes the listener. A second wallet request starts from Crypton's foreground rather than attempting to launch another app from background execution.

The bridge permits only the public-identity/authentication, read-only certificate discovery, Crypton encryption/HMAC and native-authorized MessageBox subset. It cannot access arbitrary wallet methods. The page loads only the packaged script, disallows framing/remote code and direct cross-origin networking, and sends no wallet result in a deep link. HTTP parsing rejects duplicate headers, transfer encodings, oversized headers/bodies and extra pipelined data. Connections and idle time are bounded.

## Cancellation and iOS limits

A background task is finite. If iOS ends the available background time, Crypton ends the background task but preserves the pending request, capability and any received response for foreground return. Each wallet request has a five-minute deadline; the enclosing crypto/delivery operation has a fifteen-minute deadline. Explicit cancellation or wallet deadline expiry invalidates the capability. The wallet may already have performed a requested payment, so an expired or cancelled paid request remains uncertain in the outbox. The app never resets that record into a payable draft. Device locking can also make file-protected journals unavailable until unlock.

Approve promptly, then use **Return to Crypton**. If the request expires, return to Crypton and retry the operation or use outbox recovery when a payment was requested. The implementation does not use background audio or unsupported background modes to keep the bridge alive.

## Compatibility evidence

The actual local Metanet Explorer source confirms the `metanet` iOS URL scheme and `browser?url=` route in `app.json`, `ios/Metanet/Info.plist` and `hooks/useDeepLinking.ts`. The browser uses the ReactNativeWebView CWI transport in `utils/webview/walletBridge.ts` and derives its originator from the native frame URL in `walletBridgeProtocol.ts`. The local wallet repository was read only.

Tests run the shipped page in a real WKWebView, transport requests to an independent SDK wallet, return through the callback route, and exercise normal crypto, denial, native MessageBox payment and delivery recovery. This harness validates the Crypton implementation and the observed protocol contract; it is not an installed ME app with a live user profile.

## Verification scope

The operator requested emulator-only verification. Automated tests use the dedicated Crypton iOS simulator, ad-hoc signing, a real share extension, and disposable SDK/MessageBox fixtures. Those fixtures use no live account permissions, production transactions or real funds. No physical device was used.

The simulator suite exercises the native request page, its local server, both foreground-return paths, permission denial, crypto operations, actual share-extension text/QR imports and payment/delivery recovery through an independent SDK backend. A harness supplies the observed ME CWI transport; no real account permissions or payment approvals are automated.

Separate live emulator checks on 30 October 2026 used the installed iOS and Android ME wallets and production MessageBox in both directions. Messaging permissions and payment totals were reviewed before sending. After a lost iOS wallet response, recovery found the labelled transaction, retrieved its confirmed proof and resumed delivery using the existing payment. Each receiving ME wallet displayed its notification, and Crypton decrypted the exact test plaintext. Legacy installed-wallet messages also passed in both directions.

See [the verification report](PORT_VERIFICATION.md) and [remaining-functions QA](REMAINING_FUNCTIONS_QA.md). Wallet-specific receipts and raw local experiments are excluded from publication. The automated fixtures never broadcast transactions or spend real funds.
