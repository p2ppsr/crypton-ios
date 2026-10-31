# Remaining iOS functionality checks — 30 October 2026

All work used emulators, as requested. Installed iOS/Android Crypton and Metanet Explorer were used for live interoperability. Failure tests used the separate **Crypton-iOS-Test** simulator and disposable loopback wallets. Android sources were read only.

| Requested area | Result and evidence |
| --- | --- |
| Android → iOS through production MessageBox | Passed. Android ME paid and sent, iOS ME displayed the received notification, and iOS Crypton decrypted the exact test text through native ME handoff. The received plaintext matched the sent test text exactly. |
| Legacy messaging between installed applications | Passed in both directions using the installed ME wallets. iOS required explicit selection of the Android sender for raw ciphertext. Sender identity selection and exact decrypted text were checked. |
| Original portal | Attempted; blocked by TLS connection failure to `https://mobile-portal.babbage.systems`. Crypton reports an SSL error; a host `curl` check outside the sandbox also fails during TLS setup. Portal authentication and messaging remain unverified. Certificate validation was preserved. |
| Nested messages through the UI | Passed. Enter the exact outer envelope, decrypt, inspect the outer note, choose **Open inner layer**, decrypt again, and compare the inner plaintext. |
| Phone contacts | Passed. Create a disposable Crypton contact, export its vCard, create a phone contact from that vCard, select it through Crypton's phone-contact picker, and verify the same public key returns. Deleting the disposable Crypton contact removed its row. |
| Clipboard | Passed. Copy the iOS Crypton identity and paste into the contact public-key field; compare all 66 characters. |
| Files | Passed text export/import/decryption and QR-image export/import/decryption through the actual system Files sheet. A plaintext file was rejected through the picker, preserving the existing ciphertext. Native tests additionally cover genuine PNG/JPEG QR files, invalid UTF-8, corrupt images, oversized files, unsupported URLs and legacy sender gating. |
| Photos message import | Passed using the actual Photos picker, a disposable SDK-encrypted QR and exact plaintext comparison. |
| Photos identity export/import | Passed. The UI regression checks **Share QR image → Save Image → Contacts → QR image**, then compares the imported identity to the original. The first run also exercised the expected add-only Photos permission prompt. |
| HEIC photo decoding | Passed. The runner seeds a genuine HEVC/HEIF public-identity QR; the real Photos picker loads it and Crypton returns the exact expected 66-character key. The fixture contains only a public test key. |
| Crypton share extension | Text and image share round trips are covered by the real extension and App Group, including subsequent decryption. |
| Other sharing applications | Reminders received the exact disposable test text in its draft composer; the draft was cancelled. The inspected text-share application list contained Reminders and Crypton. Assign to Contact opened the system picker. Print opened a one-page QR preview with **No Printer Selected**. Create Watch Face opened its editor with **Add** disabled. Shared Albums opened but reported **Cannot Add Items**, requiring an Apple Account and enabled Shared Albums. No reminder, contact photo, print job, Watch face or shared album was committed. |
| Insufficient funds, denied payment, denied wallet access, changed quote, lost connection | Passed with disposable wallets. No successful payment occurred in these rejection tests. An uncertain payment record cannot start another payment, including after reopening its journal. |
| Force-quit during payment | Passed using a held disposable payment response. Terminate the actual app after the wallet performs one synthetic action, relaunch, open the persisted `PAYMENT_REQUESTED` record and recover history. The UI has no new-payment action and the wallet counter remains exactly one. No real transaction was broadcast. |
| Audio | Actual simulator audio-player checks pass for foreground playback, muting/releasing both players, background silence, interruption begin/end, preserving mute during interruptions, preventing background resume and respecting the absence of `shouldResume`. Interruption notifications are simulated; actual cellular-call interruptions require hardware. |

## Changes found necessary during testing

- Replaced the cryptographic text editor's automatic text substitutions. Smart quotes and autocorrection had altered manually entered encrypted JSON. Keyboard input now preserves the received envelope exactly; the live Android reply then decrypted successfully. The nested-message UI test checks exact input equality.
- Added an audio-session interruption observer. The initial interruption test failed because players were retained and enabled foreground music did not resume correctly. The corrected implementation releases players on interruption and resumes only when permitted, active and enabled.
- Added the iOS add-only photo usage description for **Save Image**. Photo selection continues to use the private system picker rather than requesting full-library access.
- Added a Debug-only, explicitly selected MessageBox fixture journal for process-termination tests. It uses fixed loopback services and is compiled out of Release.

## Live verification and settings

Live MessageBox checks used separately reviewed wallet permissions and manually approved payments. The MessageBox quote covered server/recipient fees; wallet storage and network charges were additional. Wallet-specific receipts, raw notifications and local transaction artifacts are retained outside the published source.

Both installed applications were restored to v2 after legacy testing. The live iOS app was restored to native Metanet Explorer after the portal attempt, with sound off. No physical-device testing was performed.

## Regression results

The final expanded full suite passed **31 tests with no failures or skips**: 20 native/integration tests and 11 UI tests. It used a fresh disposable wallet, so previously saved images and encrypted files could not satisfy new round trips accidentally. The standalone bundled-engine/SDK interoperability check and unsigned iOS Release build also passed.

Reproduce the suite with `CRYPTON_SDK_ROOT` configured as described in the [README](../README.md). Set `CRYPTON_RESULT_BUNDLE` to a new path to retain your own Xcode test result bundle. Local machine logs and wallet-specific evidence are excluded from the public branch.

The final installed build was also rechecked with the actual received Android envelope: exact keyboard entry was verified, native iOS ME returned the wallet response, and the displayed plaintext matched again.

## Verification boundaries

The original portal remains blocked by the TLS failure in this environment. Third-party apps absent from the simulator, completed account-backed sharing, real printing, paired Watch installation and physical camera/call interruptions are not certified by these checks. Production insufficient-funds and permission-revocation scenarios were not induced on the funded wallets; their error handling was exercised with disposable SDK/ME bridge fixtures. The print/Watch handoffs and the Shared Albums account requirement were observed directly as described above.
