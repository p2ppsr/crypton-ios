# Crypton iOS 2.5.0 wallet-flow fixes

Approved after the recorded two-iOS-simulator run on 1 November 2026. The baseline messages were composed at 11:06:13 UTC (primary → peer) and 11:11:18 UTC (peer → primary). Both were accepted, decrypted twice and retained. The first send nevertheless left ME displaying a localhost connection error.

## Return and completion

The capability page now stops polling on operation completion, pauses command consumption/dispatch while ME is hidden, and uses ME's validated native return control exclusively. The delayed `location.href` fallback has been removed: it could outlive the completed call and navigate or interrupt a later wallet request. Duplicate response channels still have one result-save owner, and a slow acknowledgement cannot consume the next command. Results may be saved while hidden; hidden pages cannot start wallet calls.

ME checks the exact paired callback, current prompt activity and outstanding wallet calls immediately before opening Crypton. A verified Crypton localhost load failure offers **Return to Crypton** with an explicit warning to check the saved payment outcome rather than pay again. The normal browser error copy also no longer claims that an earlier wallet payment could not have completed. Error recovery UI survives loading-state changes.

Crypton explicitly sets terminal inbox/decryption statuses and ignores late intermediate progress updates after the operation finishes. No permission scopes, pairing boundaries, spending allowances or payment-recovery rules have been broadened.

## One public contact code

**My identity** shares a QR/text code with exactly these fields:

```json
{"protocol":"crypton-contact","version":1,"name":"Crypton contact","receivingKey":"<compressed public key>","walletIdentity":"<compressed public key>"}
```

Both keys are obtained in one wallet operation and validated independently. Codes are bounded to 2 KB; unknown fields, unsupported versions, invalid curve points and control characters in names are rejected. A contact code is shared public addressing information, not a certificate or an attestation binding the two keys. Obtain it from the intended person and review it before saving.

Codes work through recipient entry, identity QR/image import, file import and the share extension. Imports open a review without silently saving a contact. Saved contacts retain both keys, prefill both destinations and export both when known. Existing raw public keys and contacts remain supported. **Copy receiving key only** and the separate delivery-key action remain available for clients that do not understand contact codes, including existing Android builds.

## Shorter send flow and full costs

The composer now offers **Send with MessageBox**. It encrypts locally, creates the recoverable delivery record, checks the fee, revalidates the quote and requests ME's final payment review within one native wallet session. The session can span self-encryption as well as prepare/send. Each phase still uses the original native authorization and journal validators; completed and uncertain records cannot create another payment. Existing encrypted sharing and staged quote/review screens remain available.

ME displays the full authorization amount as **Total cost**. For matching wallet-verified Crypton line items it shows server fee, recipient fee, network fee, storage service charge and any input credit. The sum must equal the verified total; malformed or incomplete details fall back to the full total without inventing a breakdown. The prompt and confirmation identify Crypton as the requesting app, rather than claiming that Crypton receives every payment output. Payment approval remains explicit and separate from grouped permissions.

## Verification

All simulator/UI runs are recorded locally under ignored `.recordings/`; wallet videos are not committed or uploaded. Disposable fixtures cover the native capability page and real SDK/MessageBox paths. They do not spend live funds. The original two-way production result predates these fixes; a later live confirmation must be identified separately.

Verification completed across recorded dedicated-simulator runs:

- Broad run: 36 native/SDK tests and 5 UI tests passed, including offline/denied/insufficient-funds/changed-quote behavior, retained inboxes, paid recovery without another payment, force-quit protection, certified search and contact QR/photo import.
- Final model/session checks: 10 native tests and the send UI check passed, including the composer’s entire self-encryption/quotation/payment sequence opening ME exactly once.
- Contact input regression: literal JSON entry, both-key prefill and keyboard Done passed. Photo import and the send UI also passed after the exact-input change. Across these runs, 37 distinct native/SDK tests and 6 distinct UI checks passed.
- Shipped capability-page JavaScript: duplicate result channels, slow acknowledgement, hidden-page dispatch, completed-result saving, stopped polling and absence of delayed URL navigation passed.
- Companion ME: TypeScript, 13 actual native bridge regressions, Swift attribution/pairing/callback policy, payment-total/breakdown cases and tab-navigation persistence passed. Both Release simulator builds succeeded.

Installed-wallet smoke on both independent simulators preserved their identities and existing grants. Combined identity retrieval returned automatically without new wallet permissions. A deliberately reloaded, completed localhost page produced the new recovery panel; Return to Crypton restored the completed result without replaying a wallet call. The peer then decrypted the original **11:06:13 UTC** message through updated ME with a green **Message decrypted · copy retained** status. No new production send or payment was made during this smoke.

The recorded manual input check also exposed iOS smart quotes changing JSON in the previous SwiftUI key field. Key/contact-code entry now uses the same exact-input traits as the encrypted-message editor and provides a keyboard Done action. The first typed-code UI assertion exposed the keyboard covering Continue; the Done action and passing rerun cover that interaction. Initial compile/harness/test failures and their recordings are retained locally rather than discarded.

Private local recording labels include `approved-ux-regressions-final`, `ux25-final-self-send-and-status`, `ux25-contact-keyboard-final`, `ux25-primary-no-payment-smoke` and `ux25-peer-no-payment-smoke`. Public Git history contains source/documentation only.

## 2.5.1: long-review handoff recovery

The first post-2.5.0 production run exposed a remaining transport failure. A long ME review can outlast Crypton's iOS background allowance. Crypton may receive a wallet result, advance the engine and queue its next method while ME loses the HTTP acknowledgment. The old result then received a stale-UUID rejection; the hidden ME page could stop before dispatching the pending authentication. Separately, local operation timers could expire while ME still displayed its payment approval.

Version 2.5.1 (build 10) retains a bounded, session-only SHA-256 digest of accepted responses. An identical retry under the exact capability and Origin receives an acknowledgment without invoking the wallet again. Changed responses, unknown IDs and wrong origins remain rejected. Delayed HTTP completion callbacks are pinned to their request ID and cannot finish a subsequent method. The cache is cleared when the capability closes.

A validated return during an unfinished operation marks it for wallet resumption. Crypton renews its background allowance and opens ME for the next queued wallet method, including when it was queued during the inactive-to-active transition. Session responses wait for the HTTP save acknowledgment rather than advancing merely because Crypton foregrounded. The normal flow still uses one ME visit; background recovery can require another automatic visit.

Native ME payment review (`createAction`) waits for the user's decision or explicit cancellation. Crypton's general operation deadline pauses for that validated payment call and starts afresh afterward. Other wallet and network requests retain bounded timeouts. Canceling, terminating or losing the wallet preserves the existing payment journal and does not authorize a replacement payment. This is a transport/lifecycle change; ME 1.2.1 build 209 and existing wallet grants remain compatible.

Verification: the dedicated recorded simulator passed ten native wallet tests, including lost acknowledgments, stale callbacks, the foreground transition and payment review beyond a shortened ordinary request timeout. The final focused run also passed paid-delivery recovery and the one-visit composer integration (12 tests total). The complete SDK/MessageBox integration suite passed all 12 tests before the final timeout adjustment; the affected paid-recovery/composer cases were rerun afterward. All three shipped-page JavaScript regression scenarios passed. Release build succeeded.

Production evidence is deliberately narrower: primary-to-peer message composed 2026-11-01 12:01:09 UTC (`ux25-A-120109`) was accepted after a saved-payment retry, decrypted twice and retained. Peer-to-primary reply composed 12:17:16 UTC (`ux25-B-121716`) halted with PAYMENT_REQUESTED. Subsequent approved read-only ME diagnostics confirmed Pay once at 12:33:29 UTC, followed by `processAction` rejecting an already-failed action before storage commitment; cleanup then masked that error with an invalid-reference failure. There is no usable saved payment for this attempt. The old journal remains protected because it did not receive machine-verifiable non-commitment evidence. The provider status transition is tracked in [ME issue #81](https://github.com/p2ppsr/metanet-explorer-mobile/issues/81). This interrupted run does not establish a successful post-fix two-way production result. Private videos and exact transaction evidence remain local under `.recordings/`.

The first native regression launch exposed a macOS Bash empty-array error in the test runner, before any tests ran. The runner now always provides a unique xcresult destination. An initial broader integration launch used an SDK-only dependency directory, so the MessageBox service was missing; that failed recording is retained. Installing the repository's pinned complete fixture dependencies and rerunning produced the passing result above.

## Companion ME build 210: payment-review lifecycle

ME 1.2.1 build 210 adds a conservative two-minute client review deadline, checked in the UI, at grant time and immediately before signing. Expiry rejects unapproved waiters and requires a fresh review; it never silently rebuilds a transaction or reuses approval. Explicit pre-sign expiry uses the existing non-commitment signal understood by Crypton's same-wallet/fresh-history recovery. Actual signing/storage failures remain uncertain.

The wallet keeps a failed action blocked even when abort cleanup fails, and preserves the primary error instead of replacing it with the abort error. Session-local diagnostic events correlate review age, approval, expiry, finalization and cleanup without adding action references or transaction data to the new fields. See [the companion implementation and monitoring guide](https://github.com/p2ppsr/metanet-explorer-mobile/blob/codex/crypton-wallet-usability/docs/qa/crypton-payment-review.md).

This client deadline is not a verified server reservation lifetime or a fix to the provider's unknown failed-status transition. New successful production sends must be reported separately from fixture and no-spend expiry verification. Existing uncertain records are preserved, including the original 12:17:16 UTC reply.


## 2.5.2: retain the terminal result until it is acknowledged

The first no-spend installed expiry check exposed a second handoff gap: ME correctly rejected the review, but its expired modal blocked native return until Crypton's eight local save attempts were exhausted. The old page discarded that result. Crypton 2.5.2 (build 11) retains the terminal wallet response in page memory and resumes saving that exact result after manual return, accepted native return or visibility restoration. It never re-invokes the wallet method. This is in-memory retention, not force-quit persistence; saved payment-journal recovery still applies if the page/process is lost.

Companion ME build 210 dismisses an expired rejected prompt after a brief notice, allowing automatic return and result saving. Its close callback checks the exact request ID so it cannot dismiss a newer request. The Pay callback independently rejects expiry after timer suspension; the periodic check also closes a review already rejected by that callback.

Verification on 2026-11-01:

- Release builds of Crypton 2.5.2 and ME 1.2.1 build 210 installed in place on both registered iOS simulators, preserving wallets and grants.
- All four shipped-page JavaScript regressions passed, including exhausting every save retry, then returning manually and saving the same result with exactly one wallet invocation. Ten native wallet tests and two affected payment/composer integration tests passed (12 total).
- Actual pinned toolbox SDK tests passed seven scenarios, including a failed storage/signing action whose abort also fails. The original error object survives; signing/storage failures stay uncertain. UI/queue regressions cover duplicate taps, expiry after timer suspension and stale dismissal callbacks. Type checking and permission-wiring checks passed.
- Recorded installed-app message `issue81-final-155801`, composed **2026-11-01 15:58:01 UTC**, was deliberately left unpaid. The review expired at **16:01:13 UTC**, ME returned automatically, and Crypton saved the definitive expiry refusal. The original wallet's empty history then enabled **Retry declined payment**, which returned this test record to DRAFT without requesting or making a payment. Diagnostic capture: **1 review, 3 events, 1 expiry, 0 approvals, 0 finalizations, 0 cleanup failures, 0 violations**. Its private H.264 MP4 is finalized and retained with the diagnostic JSON.

The first installed run's handoff failure and the final successful expiry/recovery run are both retained. The final Pay-after-suspension close refinement is covered by the component regression; it was not separately triggered in a funded wallet. No new paid two-way production send is claimed. The provider's original failed-status transition remains open in ME issue #81.


## 2.5.3: one authenticated session before payment review

The recorded normal message `speed-164926`, composed **2026-11-01 16:49:26 UTC**, reached the final Pay review 17.901 seconds after Send and was accepted 27.667 seconds after Send. Its separate prepare/send engine invocations each constructed an AuthFetch client, repeating the server authentication handshake despite sharing one ME page.

The immediate composer send now runs both phases within one engine operation and one AuthFetch instance. Native authorization remains phase-specific: only a successfully validated and durably saved prepared checkpoint enables the send phase. The current wallet identity is checked again, the quote is fetched and compared again, and payment results are journaled before submission. Standalone fee checks, subsequent sends and recovery create fresh clients; no authenticated session is stored globally or reused across operations or wallets.

Local `Crypton pipeline` diagnostic lines now include an operation ID, a fixed stage name and monotonic elapsed milliseconds for engine completion, delivery-wallet calls, allowed HTTP requests and saved checkpoints. They contain no wallet identity, message, amount, transaction or request arguments. Completion from an old cancelled operation cannot be attributed to a newer one. These events make the next recorded run measurable without relying on screenshot observation times.

Four recorded native/SDK integration tests passed: a complete immediate send uses one handshake and two quote requests; a changed second quote produces zero payment attempts; composer encryption and sending still share one wallet visit; lost responses retain protected recovery without a second payment. All four shipped ME-page JavaScript regressions also passed. The initial test launch was stopped during compilation after an incorrect test-class selector was noticed; its recording is retained and is not counted as a pass. The corrected run executed four tests with zero failures.

This removes a verified duplicate handshake. It does not claim a particular live speedup: the 17.901-second measurement includes cold ME startup, wallet storage reads and network response time. A subsequent comparable timed run is needed to measure the remaining delay. ME build 210 is sufficient; this optimization changes only Crypton.
