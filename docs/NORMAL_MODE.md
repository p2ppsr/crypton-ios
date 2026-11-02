# Normal and advanced modes

Normal mode is the default. The first screen is the message composer, including on a new installation:

1. Enter a name, email or handle in the recipient search box. Saved contacts filter locally; tap the search icon or the keyboard Search key to ask the selected wallet for certified identities.
2. Choose a person from the dropdown. Results show the name and certification so the user can make an explicit selection. Changing the query invalidates the previous selection and preserves the message draft.
3. Write the message and tap **Send**. The action encrypts, prepares delivery and requests the wallet's payment review through the existing validated pipeline. Send stays disabled until a recipient and nonempty message are present. A contact without delivery information requires the recipient's complete Crypton contact code.

The wallet remains responsible for permissions and the full payment total. Normal mode does not approve access, spending or changes to a wallet profile.

After encryption, the actual ciphertext is previewed for half a second before delivery preparation begins. Hovering a pointer over the preview, or pressing and holding on a touch screen, pauses that timer. Releasing the preview lets it continue. **Cancel send** stops the operation before a delivery/payment intent is created. The preview also pauses while Crypton is inactive. It displays ciphertext, not the plaintext or a simulated animation.

## Everyday navigation

- **Send:** recipient search, selected recipient, message and Send.
- **Inbox:** refresh, select, decrypt and reopen retained messages. Copy and share opened plaintext remain available.
- **Sent:** readable delivery states and the existing saved-payment recovery actions. Server acceptance does not claim the recipient has read the message.
- **Contacts:** save a shared Crypton contact code, scan a contact QR and share your own combined contact code.
- **Settings:** wallet connection, pairing-code comparison, usage help and Advanced mode.

Technical public keys, server addresses, payment transaction IDs and receipt IDs are hidden in normal mode. Recipient certification, payment review and recovery outcomes remain visible.

## Advanced mode

Enable **Settings → Advanced mode** to access the original manual encryption/decryption and QR/file tools, separate receiving/delivery keys, wallet selection and endpoints, legacy formats, disappearing-message controls, dismissed-message controls, phone-contact import, sound settings and wallet-session reset.

Mode selection persists. Switching modes changes presentation; it does not change the wallet connection, permissions, legacy format, retention choices, contacts, encrypted records or saved payment recovery. Previously enabled disappearing behavior remains active and is visibly identified in normal mode. New installations keep message copies and leave sound off. Existing sound preferences are preserved.

Incoming nested content remains openable so a normal-mode recipient can read a message sent by an advanced user. Imported messages and contact codes retain the existing validators.

## Verification

The normal-mode UI checks use the dedicated recorded simulator and disposable SDK/MessageBox fixtures. They cover first-screen controls, certified search and selection, encrypted sending, exact inbox decryption and retention, and returning from Advanced mode to the simple composer. Existing advanced flows have explicit advanced-mode test setup. Native checks cover persisted mode selection and preservation of existing wallet/privacy settings. No live wallet grant or payment is automated.

Detailed test results, screenshots and MP4s stay local in the ignored `.recordings/` directory. Simulator checks do not establish physical-iPad compatibility or production delivery timing.
