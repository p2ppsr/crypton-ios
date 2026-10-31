# Wallet flow and grouped permissions — 2.4.1

This change addresses the eight problems found during the 31 October 2026 live Moto e13 send. It changes both Crypton and Metanet Explorer. The successful production message predates these fixes; its acceptance is not evidence that the new grouped flow has been tested with production funds.

## Standards reviewed

- [Project Babbage: Wallet Storage and Management](https://projectbabbage.com/wallet-storage-management): unified wallet capabilities and extensible permission schemes.
- [BRC-116: Wallet Permissions and Counterparty Trust](https://github.com/bsv-blockchain/BRCs/blob/master/wallet/0116.md): manifest groups, per-scope selection, persistence, denial, revocation and separation of spending from protocol grants.
- [BRC-100: Wallet Interface](https://github.com/bsv-blockchain/BRCs/blob/master/wallet/0100.md): the underlying wallet operations remain standard CWI calls.

The native-app origin attribution and callback control are an ME implementation extension, not additional BRC-100 wallet methods. Web applications continue using their native frame hostname. Crypton never supplies an arbitrary originator in page JSON.

## Changes

| Observed problem | Change |
| --- | --- |
| An app switch for every wallet call | One capability-scoped ME page per engine operation; subsequent validated calls use its existing queue. Re-entry targets the current browser tab. |
| Return link unreliable | Updated ME handles an exact native callback control message, after checking the registered page and wallet-prompt state. No wallet result or keys appear in the callback URL. Older ME supports the manual app-switcher fallback. |
| Authentication exceeded 120 seconds during approvals | The authentication exchange now shares the bounded 15-minute engine budget. Individual ME approvals retain a five-minute deadline and native HTTP requests retain their independent network/response-size limits. |
| Payment approval canceled by app switching | No return is attempted while a CWI invocation is pending. ME independently refuses the callback while any native wallet prompt is active. A completed response is retried without re-invoking the wallet operation. |
| Old quote expired during re-authentication | Before payment, retrieve a fresh authenticated quote, compare all fees and the pinned server identity, and checkpoint its native timestamp. Changed fees still require a fresh review; an unchanged old review can continue against a newly checked quote. |
| Permissions reappeared after Allow | Bundle a reviewed group manifest in ME, establish a stable native identity from UIKit attribution, and hold individual permission waiters until persistent grants finish saving. A persistence failure rejects the waiting call. Existing canonical-token revocation and profile isolation remain enforced. |
| Canceled request stuck without useful recovery | Show a human-readable empty-history outcome. A typed ME refusal from a pre-commit permission check plus fresh empty history from the original wallet enables **Retry declined payment**. Generic errors, background cancellation, lost responses and empty history alone never enable another payment. |
| Generic or misleading status | Show identity, authentication, fee, payment-review, submission and history-check phases. Recovery displays outcomes in plain language rather than raw JSON. |

The server issues each wallet command at most once. A refreshed or duplicate page cannot fetch the same command again. Losing a command/response can require conservative recovery; it must not silently create another payment.

## Group scope

The capability page serves `Engine/manifest.json`. Updated ME uses a wallet-bundled copy of the reviewed declaration, scoped to `crypton.native`, only after UIKit identifies the source app as `com.projectbabbage.Crypton` and registers that exact localhost capability URL. Unattributed localhost pages retain their ordinary localhost identity. A website claiming `crypton.native` is rejected. Contexts are bounded and expire after 15 minutes.

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

Use only the dedicated `Crypton-iOS-Test` simulator and disposable SDK/MessageBox fixtures. No funds or new production permissions are required for the automated tests. See the final verification results below; authenticated production permission persistence and another paid phone delivery require a separately reviewed live wallet interaction.

### Results on 31 October 2026

- Crypton: 33 native/SDK integration tests passed. Seven wallet transport checks passed again after the final queue/replay changes.
- All 16 UI cases passed across the main run and the targeted recovery rerun. One assertion initially expected raw `unsigned` JSON; it was updated to assert the new visible “Wallet preparation pending” status, preserving its no-second-payment check.
- ME: TypeScript checking, actual Swift attribution policy, real Toolbox grouped routing/selection with disposable persistence, permission settlement, canonical permission cache/revocation, byte bridge, discovery bridge and money-UX checks passed.
- Crypton 2.4.1 (8) and ME 1.2.1 (208) simulator Release builds succeeded. Native integration was also built against the minimal checked-in iOS project wiring.
- No production grouped grant or new paid message was approved during these automated checks. Physical-device behavior was not tested, as requested.

A simulator update must retain the installed native bundle identity and its matching embedded Expo configuration; the official and Bob wallet builds have different authentication/app-group settings. Cached Bob artifacts must not be treated as evidence of the installed official wallet configuration. Permission migration between native identities is intentionally not automatic.

The installed official ME smoke check reached its wallet welcome screen. Presence checks confirmed saved encrypted snapshots are retained; no snapshot, credential or key contents were exported or displayed. A production grouped grant, automatic return from that grant, and a new paid send remain unverified until the existing wallet is reopened and the user reviews the new scopes.
