# Wallet flow and grouped permissions — 2.4.1

This change addresses the eight problems found during the 31 October 2026 live Moto e13 send. It changes both Crypton and Metanet Explorer. The successful production message predates these fixes; its acceptance is not evidence that the new grouped flow has been tested with production funds.

## Standards reviewed

- [Project Babbage: Wallet Storage and Management](https://projectbabbage.com/wallet-storage-management): unified wallet capabilities and extensible permission schemes.
- [BRC-116: Wallet Permissions and Counterparty Trust](https://github.com/bsv-blockchain/BRCs/blob/master/wallet/0116.md): manifest groups, per-scope selection, persistence, denial, revocation and separation of spending from protocol grants.
- [BRC-100: Wallet Interface](https://github.com/bsv-blockchain/BRCs/blob/master/wallet/0100.md): the underlying wallet operations remain standard CWI calls.

The native-app attribution/pairing and callback control are an ME implementation extension, not additional BRC-100 wallet methods. Web applications continue using their native frame hostname. Crypton never supplies an arbitrary originator in page JSON.

## Changes

| Observed problem | Change |
| --- | --- |
| An app switch for every wallet call | One capability-scoped ME page per engine operation; subsequent validated calls use its existing queue. Re-entry targets the current browser tab. |
| Return link unreliable | Updated ME handles an exact native callback control message, after checking the registered page and wallet-prompt state. No wallet result or keys appear in the callback URL. Older ME supports the manual app-switcher fallback. |
| Authentication exceeded 120 seconds during approvals | The authentication exchange now shares the bounded 15-minute engine budget. Individual ME approvals retain a five-minute deadline and native HTTP requests retain their independent network/response-size limits. |
| Payment approval canceled by app switching | No return is attempted while a CWI invocation is pending. ME independently refuses the callback while any native wallet prompt is active. A completed response is retried without re-invoking the wallet operation. |
| Old quote expired during re-authentication | Before payment, retrieve a fresh authenticated quote, compare all fees and the pinned server identity, and checkpoint its native timestamp. Changed fees still require a fresh review; an unchanged old review can continue against a newly checked quote. |
| Permissions reappeared after Allow | Bundle a reviewed group manifest in ME, establish a stable native identity from UIKit attribution or a signed app pairing key, and hold individual permission waiters until persistent grants finish saving. A persistence failure rejects the waiting call. Existing canonical-token revocation and profile isolation remain enforced. |
| Canceled request stuck without useful recovery | Show a human-readable empty-history outcome. A typed ME refusal from a pre-commit permission check plus fresh empty history from the original wallet enables **Retry declined payment**. Generic errors, background cancellation, lost responses and empty history alone never enable another payment. |
| Generic or misleading status | Show identity, authentication, fee, payment-review, submission and history-check phases. Recovery displays outcomes in plain language rather than raw JSON. |

The server issues each wallet command at most once. A refreshed or duplicate page cannot fetch the same command again. Losing a command/response can require conservative recovery; it must not silently create another payment.

## Group scope

The capability page serves `Engine/manifest.json`. Updated ME uses a wallet-bundled copy of the reviewed declaration. [Apple restricts UIKit source-app attribution to apps on the same signing team](https://developer.apple.com/documentation/uikit/uiscene/connectionoptions/sourceapplication), which excludes ad-hoc simulator builds and independently signed apps.

Crypton therefore signs its exact localhost capability URL, public pairing key and expiry with a persistent P-256 app key in the iOS Keychain. ME verifies the signature, binds it to that exact page, limits its lifetime to 15 minutes, and derives `crypton.native.<first-32-hash-characters>.<last-32-hash-characters>` (two DNS labels containing the full SHA-256 fingerprint) as the permission identity. A different key cannot reuse existing grants. The proof contains no private key or wallet data. This key authenticates the app pairing only; it does not encrypt messages or authorize spending.

Key possession does not attest the app’s bundle identity. Crypton’s Settings and ME’s grouped review display the same short pairing code, which the user should compare before granting access. A newly generated key requires a new review. Same-team attributed older clients can use `crypton.native`; anonymous localhost pages keep their ordinary hostname identity. A website claiming either native identity is rejected. Contexts are bounded to 16 pages and expire after 15 minutes.

The grouped declaration contains:

- Public wallet identity retrieval, level 1.
- `server hmac`, level 2, explicitly **self**.
- `crypton`, level 2, explicitly **self**, for the receiving identity.
- `messagebox`, level 1.
- `auth message signature`, level 2, for the pinned MessageBox server.
- BRC-29 payment-destination derivation (`3241645161d8`), level 2, for that same server.

The user can uncheck individual scopes. If a required scope is unchecked, the current Crypton request fails without immediately presenting that same capability as a second individual prompt. Saving remembered permission tokens can incur wallet/storage fees, which the review now discloses. Revocation remains in ME's Apps & Permissions.

The group declares no standing spending limit, certificate disclosure, basket access or privileged root access. Message payments retain ME's separate review. Legacy peer-specific operations and certificate discovery can require their own narrowly scoped permissions.

## iOS suspension and recovery

A short background task permits the queue to advance while ME is foreground. iOS may suspend Crypton during a long approval. After the wallet finishes, the bridge can return to Crypton and retry saving the same response; it never repeats the wallet call. An unanswered/in-progress wallet invocation does not trigger that return. Background audio is not used.

A callback from an older ME build may still require manually returning once after the operation finishes. The automatic attributed return and grouped native identity require the companion ME update.

Historical `PAYMENT_REQUESTED` records with only a generic code-1/background-cancellation error cannot acquire definitive refusal evidence retroactively. They remain protected. Empty wallet history does not establish that an interrupted backend operation can never complete.

## Verification

Run automated tests only on the dedicated `Crypton-iOS-Test` simulator with disposable SDK/MessageBox fixtures. Those tests require no funds or production grants. The separately approved installed-wallet checks are recorded below; another paid phone delivery after these changes remains unverified.

### Results on 31 October 2026

- Crypton: 33 native/SDK integration tests passed. Eight wallet transport/pairing checks and two WKWebView/SDK integration tests passed again after the final pairing and dual-response changes.
- All 16 UI cases passed across the main run and the targeted recovery rerun. One assertion initially expected raw `unsigned` JSON; it was updated to assert the new visible “Wallet preparation pending” status, preserving its no-second-payment check.
- ME: TypeScript checking, actual Swift attribution policy, real Toolbox grouped routing/selection with disposable persistence, permission settlement, canonical permission cache/revocation, byte bridge, discovery bridge and money-UX checks passed.
- Crypton 2.4.1 (8) and ME 1.2.1 (208) simulator Release builds succeeded. Native integration was also built against the minimal checked-in iOS project wiring.
- No production grouped grant or new paid message was approved during these automated checks. Physical-device behavior was not tested, as requested.

A simulator update must retain the installed native bundle identity and its matching embedded Expo configuration; the official and Bob wallet builds have different authentication/app-group settings. Cached Bob artifacts must not be treated as evidence of the installed official wallet configuration. Permission migration between native identities is intentionally not automatic.

The final Xcode-signed installed apps launch successfully. The saved encrypted snapshots are retained and the installed ME wallet retrieved Crypton’s receiving identity. No snapshot, credential or key contents were exported or displayed. The operator subsequently approved the six-scope group; its persistence and reuse are verified below. A new paid send after these changes remains unverified.

### Installed-bridge follow-up

ME sends wallet responses through both `postMessage` and injected message events. The bridge now claims a response UUID synchronously before saving it, so both channels cannot start competing save/recovery loops. Polling pauses until that save is acknowledged, preventing a one-time command from being fetched and lost while a previous response is still pending. Explicit manual return can retry an exhausted return request.

The return control now passes a nonempty ID through ME’s actual message sender; without it, that sender discarded the acknowledgement. Eleven native discovery/return-handler regression cases pass, including acknowledgement when a native prompt blocks return. The shipped page also passes a deterministic dual-channel/slow-acknowledgement regression. Two WKWebView/SDK integration tests pass with duplicate responses emitted as installed ME emits them, covering identity/crypto/denial and paid-delivery recovery with no second payment.

### Installed simulator evidence

The installed official ME now presents all six selectable Crypton scopes together and displays the same pairing code as Crypton Settings. The preceding denied request returned automatically to Crypton. The operator subsequently approved the group. Saved-grant inspection and reuse passed; live revocation and a new paid production message were not performed. The final review uses a readable **Allow selected** button and displays the complete permission-storage cost disclosure.

The full fingerprint is split into two DNS labels because Toolbox enforces the 63-character per-label limit. The real manager’s originator validator and grouped-permission routing/selection now test that exact native identity format. Unsigned websites cannot use it.

### Approved grant and restart verification — 31 October 2026

The operator approved the six-scope group in installed iOS ME. A second wallet-identity request completed without another permission prompt and returned automatically to Crypton. After updating/restarting ME in place, another fresh request returned the same wallet identity without reapproval. ME’s Apps & Permissions listed all six stored protocol grants under the matching Crypton pairing identity, with **No remembered limit** for spending. The existing ME browser tab was reused. No new message payment or grant revocation was initiated by the agent.

This verification exposed and corrected a management-view mismatch: the browser’s wallet controls initially used the page’s `localhost` hostname instead of the verified native identity. The view now resolves that exact tab URL to the previously verified pairing identity before listing or revoking grants. A bounded, persistent map of at most 128 verified page identities lets the owner manage grants after a capability expires. This metadata never authenticates wallet calls or permits an expired callback; the active request context retains its independent 15-minute expiry.

Actual Swift policy tests cover that separation after capability expiry, forged-page rejection, and native signing identity. JavaScript tests cover management-only lookup, rejection of unverified native-looking hostnames, and unchanged ordinary-site behavior. TypeScript, permission-refresh failure/stale-result regressions, and mobile wallet UX checks pass. The companion simulator Release build and installed management screen were verified.

### Cold-cache MessageBox authentication — 1 November 2026

The retained-message production run exposed a remaining path that the identity-only restart test did not exercise: ME’s direct HMAC bridge skipped durable token lookup after its short-lived cache expired, then requested the already granted level-1 MessageBox scope individually. The duplicate prompt was dismissed without creating another grant.

For verified Crypton identities, the bridge now checks the existing canonical protocol token, its exact scope and expiry before prompting. It does not use the process-global recent-grant shortcut for these identities. Missing authority goes through the grouped permission manager; an offline token lookup fails without starting a replacement grant. Other applications keep their existing interactive behavior.

Twelve actual native bridge regression cases pass, including cold-cache reuse, denied/missing grants and offline failure. TypeScript and the simulator Release build pass. After installing the correction, the same retained draft completed authenticated production fee lookup without another permission prompt and returned automatically to Crypton. MessageBox quoted its server/recipient fees; wallet payment review remained separate.
