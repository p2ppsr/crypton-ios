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
