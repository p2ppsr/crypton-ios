import SwiftUI
import Contacts
import UniformTypeIdentifiers

private let mint = Color(red:0,green:0.92,blue:0.70)
private let panel = Color(red:0.06,green:0.10,blue:0.15)
private struct SharedItems { let id = UUID(); let items:[Any] }
private enum Modal: Identifiable {
    case scanner, photo, contacts, share(SharedItems)
    var id:String { switch self { case .scanner:return "scanner"; case .photo:return "photo"; case .contacts:return "contacts"; case .share(let value):return value.id.uuidString } }
}

struct CryptonView: View {
    @StateObject var model = AppModel()
    @Environment(\.scenePhase) var scenePhase
    @State private var modal: Modal?
    @State private var scanIdentity = false
    @State private var filePicker = false
    @State private var clearConfirm = false
    @State private var copied = false
    var body: some View {
        ZStack {
            Color(red:0.025,green:0.045,blue:0.075).ignoresSafeArea()
            VStack(spacing:0) {
                HStack {
                    Button { model.screen = .home } label: { Text("CRYPTON").font(.system(.title3,design:.monospaced,weight:.bold)).tracking(4) }
                        .accessibilityLabel("Crypton home")
                    Spacer()
                    Button { model.screen = .settings } label: { Image(systemName:"gearshape").font(.title3) }.accessibilityLabel("Settings")
                }.padding(.horizontal,24).padding(.vertical,18)
                Button { model.connect() } label: {
                    HStack { Circle().fill(model.status == "Wallet connected" ? mint : .orange).frame(width:7,height:7); Text(model.status).font(.footnote); Spacer(); Image(systemName:"arrow.up.right") }
                        .foregroundStyle(.white.opacity(0.7)).padding(14).background(panel,in:RoundedRectangle(cornerRadius:10))
                }.padding(.horizontal,24).padding(.bottom,10).accessibilityIdentifier("walletStatus")
                ScrollView {
                    VStack(alignment:.leading,spacing:18) { content }
                        .frame(maxWidth:620,alignment:.leading).padding(24).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.disabled(model.busy)
            if model.busy {
                VStack(spacing:18) { ProgressView().tint(mint); Text("Waiting for your wallet…"); Button("Cancel request") { model.cancel() }.tint(mint) }
                    .padding(28).background(panel,in:RoundedRectangle(cornerRadius:18)).shadow(radius:30)
            }
            if (model.disappearSend || model.disappearReceive || model.privateInboxView) && (!model.foreground || model.captureActive) {
                Color(red:0.025,green:0.045,blue:0.075).ignoresSafeArea().overlay { Text("Crypton · private view hidden").foregroundStyle(mint) }
            }
        }
        .foregroundStyle(.white).tint(mint).preferredColorScheme(.dark)
        .sheet(item:$modal) { item in
            switch item {
            case .scanner: NavigationStack { QRScanner { received($0) }.ignoresSafeArea().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { modal = nil } } } }
            case .photo: PhotoImporter { received($0) }
            case .contacts: PhoneContacts { value in
                modal = nil
                switch value { case .success(let pair): model.contactName = pair.0; model.keyDraft = pair.1
                case .failure(let error): model.error = error.localizedDescription }
            }
            case .share(let payload): ShareSheet(items:payload.items) { model.importPendingShare() }
            }
        }
        .sheet(isPresented:$model.portalVisible,onDismiss:{ if model.busy { model.cancel() } }) {
            if let portal = model.portal {
                NavigationStack { WalletWebView(web:portal.web).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close wallet") { model.cancel() } } }.navigationTitle("Wallet").navigationBarTitleDisplayMode(.inline) }
                    .interactiveDismissDisabled(model.busy)
            }
        }
        .alert("Crypton",isPresented:Binding(get:{ model.error != nil },set:{ if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog("Clear the wallet session? Drafts and results will be cleared. Saved contacts and encrypted outbox records will remain.",isPresented:$clearConfirm,titleVisibility:.visible) { Button("Clear wallet session",role:.destructive) { model.clearSession() } }
        .fileImporter(isPresented:$filePicker,allowedContentTypes:[.json,.plainText,.image],allowsMultipleSelection:false) { result in
            switch result { case .success(let urls): if let url = urls.first { model.importURL(url) }
            case .failure(let error): model.error = error.localizedDescription }
        }
        .onOpenURL { model.importURL($0) }
        .onReceive(NotificationCenter.default.publisher(for:UIScreen.capturedDidChangeNotification)) { _ in model.captureActive = UIScreen.main.isCaptured }
        .onReceive(NotificationCenter.default.publisher(for:.cryptonImport)) { if let url = $0.object as? URL { model.importURL(url) } }
        .onChange(of:scenePhase) { phase in model.active(phase == .active) }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)) { _ in model.active(true) }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification)) { _ in model.active(false) }
        .onAppear { model.active(true) }
    }
    @ViewBuilder private var content: some View {
        switch model.screen {
        case .home: home
        case .recipient: recipient
        case .compose: compose
        case .result: result
        case .contacts: contacts
        case .settings: settings
        case .guide: guide
        case .outbox: outbox
        case .delivery: delivery
        case .inbox: inbox
        case .inboxMessage: inboxMessage
        }
    }
    private func title(_ text:String,_ subtitle:String = "") -> some View {
        VStack(alignment:.leading,spacing:12) { Text(text).font(.system(size:32,weight:.bold,design:.rounded)); if !subtitle.isEmpty { Text(subtitle).font(.body).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal:false,vertical:true) } }
    }
    private func action(_ title:String,_ icon:String = "arrow.right",primary:Bool = false,_ work:@escaping () -> Void) -> some View {
        Button(action:work) { HStack(spacing:14) { Image(systemName:icon).frame(width:22); Text(title).fontWeight(.semibold); Spacer(); Image(systemName:"chevron.right").font(.caption) }.padding(18).frame(maxWidth:.infinity).foregroundStyle(primary ? Color.black : .white).background(primary ? mint : panel,in:RoundedRectangle(cornerRadius:14)) }
    }
    private func textField(_ label:String,_ value:Binding<String>,key:Bool = false) -> some View {
        TextField(label,text:value,axis:.vertical).font(key ? .system(.body,design:.monospaced) : .body).textInputAutocapitalization(.never).autocorrectionDisabled().padding(16).background(panel,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel(label)
    }
    private func selectable(_ value:String) -> some View {
        Text(value).font(.system(.footnote,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(16).background(panel,in:RoundedRectangle(cornerRadius:12))
    }
    private func back(_ screen:Screen = .home) -> some View { Button("Back") { model.screen = screen }.padding(.vertical,8) }
    private var home: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("PRIVATE BY DESIGN").font(.system(.caption,design:.monospaced,weight:.bold)).tracking(3).foregroundStyle(mint)
            title("A secret worth\nsharing.","Turn a message into an encrypted QR code. Only its recipient can open it.")
            Image("logonew").resizable().scaledToFit().frame(height:104).frame(maxWidth:.infinity).padding(.vertical,14).accessibilityHidden(true)
            action("New message","square.and.pencil",primary:true) { model.begin(decrypt:false) }
            action("Decrypt message","lock.open") { model.begin(decrypt:true); model.legacySenderSelected = false }
            HStack(spacing:16) {
                homeTile("My identity",icon:"person.crop.square") { model.identity() }
                homeTile("Contacts",icon:"person.2") { model.decrypting = false; model.screen = .contacts }
            }
            action("MessageBox outbox","tray") { model.screen = .outbox }
            action("MessageBox inbox","tray.and.arrow.down",primary:true) { model.showInbox() }
            Text("Your wallet holds your root keys. Crypton stores public contacts and encrypted message records.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func homeTile(_ text:String,icon:String,work:@escaping () -> Void) -> some View {
        Button(action:work) {
            VStack(spacing:12) { Image(systemName:icon).font(.title2); Text(text).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8) }
                .frame(maxWidth:.infinity).frame(height:96).background(panel,in:RoundedRectangle(cornerRadius:14))
        }.foregroundStyle(.white)
    }
    private var recipient: some View {
        VStack(alignment:.leading,spacing:18) {
            title(model.decrypting ? "Choose sender" : "Choose recipient",model.decrypting ? "For legacy ciphertext, choose the identity that encrypted it." : "Search certified identities, or use a receiving key shared by your friend.")
            action("Myself","person",primary:true) { model.legacySenderSelected = true; model.choose("self",name:"Myself") }
            if !model.decrypting { recipientSearch }
            textField("Identity public key",$model.keyDraft,key:true)
            action("Continue",primary:true) { model.legacySenderSelected = true; model.choose(model.keyDraft) }
            identityImports
            ForEach(model.contacts) { contact in action(contact.name,"person.crop.circle") { model.chooseContact(contact) } }
            back(model.decrypting ? .compose : .home)
        }
    }
    private var recipientSearch: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("FIND WITH SOCIALCERT").font(.caption).foregroundStyle(mint)
            textField("Email, social handle or name",$model.recipientQuery)
                .accessibilityIdentifier("recipientSearchQuery")
            action("Search","magnifyingglass",primary:true) { model.searchRecipients() }
            Text("Search uses your wallet’s trusted certificates and publicly discoverable fields. In ME, complete the request and return to Crypton.").font(.footnote).foregroundStyle(.secondary)
            ForEach(model.searchResults) { identity in
                VStack(alignment:.leading,spacing:10) {
                    Label(identity.name,systemImage:"person.crop.circle").font(.headline)
                    Text(identity.certification).font(.subheadline).foregroundStyle(mint)
                    Text("Wallet identity").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) { Text(identity.key).font(.system(.caption,design:.monospaced)).textSelection(.enabled).fixedSize() }
                    DisclosureGroup("Certifier public key") {
                        ScrollView(.horizontal) { Text(identity.certifier).font(.system(.caption,design:.monospaced)).textSelection(.enabled).fixedSize() }
                    }
                    Button("Use this recipient") { model.chooseDiscovered(identity) }
                        .accessibilityIdentifier("selectRecipient-" + identity.key)
                }.padding(16).background(panel,in:RoundedRectangle(cornerRadius:14))
            }
            if model.searchCompleted {
                Text(model.searchResults.isEmpty ? "No matching identities returned by your wallet. Check the spelling, public certificate publication and wallet trust settings, or enter a receiving key below." : "Showing up to 20 certificates. Refine your search if needed. Confirm the identity before selecting it.")
                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("recipientSearchSummary")
            }
        }
    }
    private var identityImports: some View {
        HStack {
            Button("Scan identity",systemImage:"qrcode.viewfinder") { scanIdentity = true; modal = .scanner }
            Spacer()
            Button("QR image",systemImage:"photo") { scanIdentity = true; modal = .photo }
        }.font(.subheadline).padding(.vertical,8)
    }
    private var compose: some View {
        VStack(alignment:.leading,spacing:18) {
            title(model.decrypting ? "Open a secret." : "Write a secret.")
            if model.decrypting && Wire.isEnvelope(model.ciphertext) { Label("Sender included in v2 envelope",systemImage:"checkmark.shield").font(.subheadline).foregroundStyle(mint) }
            else { HStack { Text((model.decrypting ? "From: " : "To: ") + model.peerName); Spacer(); Button("Change") { model.screen = .recipient } } }
            if !model.decrypting, let identity = model.selectedIdentity {
                Text(identity.certification).font(.footnote).foregroundStyle(mint)
                Text("This certified wallet identity will receive the encrypted message and MessageBox delivery.").font(.footnote).foregroundStyle(.secondary)
                Button(model.recipientSaved ? "Recipient saved" : "Save recipient contact") { model.saveDiscoveredRecipient() }.disabled(model.recipientSaved)
            }
            Text(model.decrypting ? "Encrypted text" : "Your message").font(.subheadline).foregroundStyle(.secondary)
            MessageEditor(text:model.decrypting ? $model.ciphertext : $model.message).padding(12).frame(height:230).background(panel,in:RoundedRectangle(cornerRadius:12))
                .onChange(of:model.message) { value in if value.utf16.count > 16_000 { model.message = String(value.prefix(16_000)) } }
                .onChange(of:model.ciphertext) { value in if value.utf8.count > 100_000 { model.ciphertext = String(value.prefix(100_000)) } }
            if model.decrypting {
                action("Scan encrypted QR","qrcode.viewfinder") { scanIdentity = false; modal = .scanner }
                action("Import QR image","photo") { scanIdentity = false; modal = .photo }
                Button("Import encrypted file") { filePicker = true }
            }
            action(model.decrypting ? "Decrypt message" : "Encrypt message",model.decrypting ? "lock.open" : "lock",primary:true) { model.process() }
            Text(model.decrypting ? "Nested messages open one layer at a time." : model.legacy ? "Legacy format · protocol [1, crypton]" : "Crypton v2 · each seal uses a fresh sender key. Keep your plaintext copy if you need it later.").font(.footnote).foregroundStyle(.secondary)
            back()
        }
    }
    private var result: some View {
        let identity = ["identity","walletIdentity"].contains(model.outputKind)
        let encrypted = ["encrypted","layer"].contains(model.outputKind)
        return VStack(alignment:.leading,spacing:18) {
            title(identity ? (model.outputKind == "walletIdentity" ? "Delivery wallet key" : "My identity") : model.outputKind == "layer" ? "Outer layer opened" : encrypted ? "Sealed and ready." : "Message opened.")
            if model.outputKind == "layer" {
                Text("The inner message is still encrypted.").foregroundStyle(mint)
                if !model.layerNote.isEmpty { Text(model.layerNote).textSelection(.enabled) }
                action("Open inner layer","lock.open",primary:true) { model.openInner() }
            }
            if identity || (encrypted && !model.disappearSend) {
                if let image = QRTools.image(model.output) {
                    Image(uiImage:image).interpolation(.none).resizable().scaledToFit().frame(maxHeight:300).frame(maxWidth:.infinity).accessibilityLabel(identity ? "Identity QR code" : "Encrypted QR code")
                    action("Share QR image","square.and.arrow.up") { modal = .share(SharedItems(items:[image])) }
                } else { Text("This message is too large for one QR code. Share the encrypted text instead.").foregroundStyle(.secondary) }
            }
            if model.disappearSend && encrypted { Text(model.output).font(.system(.footnote,design:.monospaced)).accessibilityIdentifier("resultText") }
            else { selectable(model.output).accessibilityIdentifier("resultText") }
            if model.outputKind == "identity" { Text(model.legacy ? "Legacy mode shares your wallet identity. Use the same format as your sender." : "Your app-only Crypton receiving key. Share it with people who want to send you v2 messages.").font(.footnote).foregroundStyle(.secondary) }
            if model.outputKind == "walletIdentity" { Text("For MessageBox delivery, share this wallet identity separately from your Crypton receiving key.").font(.footnote).foregroundStyle(.secondary) }
            if identity || !model.disappearSend {
            action(copied ? "Copied" : "Copy text","doc.on.doc") {
                model.copyText(model.output)
                copied = true; DispatchQueue.main.asyncAfter(deadline:.now()+2) { copied = false }
            }
            action("Share text","square.and.arrow.up") { modal = .share(SharedItems(items:[model.output])) }
            }
            if model.outputKind == "encrypted" && Wire.isEnvelope(model.output) { action("Send with MessageBox","paperplane",primary:true) { model.newDelivery() } }
            action("Done","checkmark",primary:true) { model.done() }
        }
    }
    private var contacts: some View {
        VStack(alignment:.leading,spacing:18) {
            title("Your contacts.","Only names and public identity keys are saved.")
            ForEach(model.contacts) { contact in
                VStack(alignment:.leading,spacing:10) {
                    Button(contact.name) { model.chooseContact(contact) }
                    Text(contact.key).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack { Button("Export contact") { export(contact) }; Spacer(); Button("Delete",role:.destructive) { model.deleteContact(contact) } }.font(.caption)
                }.padding(16).background(panel,in:RoundedRectangle(cornerRadius:12))
            }
            if model.contacts.isEmpty { Text("No contacts yet. Add a friend’s receiving key below.").foregroundStyle(.secondary) }
            textField("Contact name",$model.contactName)
            textField("Identity public key",$model.keyDraft,key:true)
            identityImports
            action("Save contact","person.badge.plus",primary:true) { model.saveContact() }
            action("Import phone contact","person.crop.rectangle") { modal = .contacts }
            Text("Phone contacts can carry a Crypton identity in a URL or instant-message field.").font(.footnote).foregroundStyle(.secondary)
            back()
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:18) {
            title("Settings.")
            Text("WALLET CONNECTION").font(.caption).foregroundStyle(mint)
            Picker("Wallet connection",selection:$model.walletMode) { Text("Metanet Explorer").tag("me"); Text("ME (Bob)").tag("me-bob"); Text("Original portal").tag("portal"); Text("BRC-100 JSON").tag("json") }.pickerStyle(.menu)
            if model.walletMode == "json" {
                textField("https://wallet.example",$model.endpoint)
                Text("Use an unlocked BRC-100 wallet with a JSON API. Requests identify this app as https://crypton.ios.").font(.footnote).foregroundStyle(.secondary)
            } else if ["me","me-bob"].contains(model.walletMode) { Text(model.walletMode == "me-bob" ? "Uses the separate iOS ME Bob app. Sign in there independently; the official wallet remains installed." : "Approve each request in Metanet Explorer, then return to Crypton.").font(.footnote).foregroundStyle(.secondary) } else { Text(PortalWallet.origin).font(.footnote).textSelection(.enabled) }
            action("Save wallet connection","checkmark",primary:true) { model.saveWallet() }
            Toggle("Legacy iPhone message format",isOn:$model.legacy).tint(mint)
            Text(model.legacy ? "Raw base64 · wallet identity · explicit sender selection" : "Crypton v2 · app-only receiving identity · sender included").font(.footnote).foregroundStyle(.secondary)
            if !model.legacy && model.walletMode == "portal" { Text("V2 identities require a BRC-100 wallet. The original portal supports legacy messages.").font(.footnote).foregroundStyle(.orange) }
            Toggle("Music and sound effects",isOn:$model.soundEnabled).tint(mint)
            Text("DISAPPEARING MESSAGES").font(.caption).foregroundStyle(mint)
            Toggle("Sent: remove after confirmed delivery",isOn:$model.disappearSend).tint(mint)
            Toggle("Received: decrypt once and remove",isOn:$model.disappearReceive).tint(mint)
            Text("Both default to Keep copies. Sent mode applies to new MessageBox deliveries and keeps uncertain payments recoverable. Received mode applies to inbox decryption: it removes the local ciphertext, automatically acknowledges the server message and verifies removal. Recipient fees are not collected; receive a wanted fee in ME first.").font(.footnote).foregroundStyle(.secondary)
            Text("Private views hide in app previews and during screen recording. iOS cannot prevent screenshots. Wallet records, server backups and copies in other apps are outside this setting.").font(.footnote).foregroundStyle(.secondary)
            action("Open wallet","wallet.pass") { model.connect(showPortal:true) }
            action("My identity","person.crop.square") { model.identity() }
            action("Import next shared message","square.and.arrow.down") { model.importPendingShare() }
            action("How Crypton works","questionmark.circle") { model.screen = .guide }
            Button("Clear wallet session",role:.destructive) { clearConfirm = true }.padding(.vertical,12)
            Text("Drafts, decrypted messages and app-only private material stay in memory. Clearing this session does not sign out an external BRC-100 wallet.").font(.footnote).foregroundStyle(.secondary)
            Text("Music: Phantom from Space — Kevin MacLeod (incompetech.com), CC BY 4.0.").font(.caption).foregroundStyle(.secondary)
            back()
        }
    }
    private var guide: some View {
        VStack(alignment:.leading,spacing:22) {
            title("Your words.\nTheir eyes only.","Encrypted messages across Crypton for iOS, Android and the web.")
            guideRow("01","Connect a wallet","Use Metanet Explorer on this iPhone for Crypton v2. Settings also offers the original portal and BRC-100 JSON wallets.")
            guideRow("02","Find a recipient","Search certified identities through your wallet, or share My identity and save a friend’s receiving key. Both people must use compatible message formats.")
            guideRow("03","Seal and share","Choose a recipient, write your message and share the encrypted text or QR image.")
            guideRow("04","Open a secret","Refresh MessageBox inbox, select a message and decrypt it. Text, QR and Files import are also available. Legacy ciphertext needs its sender selected.")
            action("Get started","arrow.right",primary:true) { model.finishGuide() }
        }
    }
    private func guideRow(_ n:String,_ heading:String,_ body:String) -> some View {
        HStack(alignment:.top,spacing:18) { Text(n).font(.system(.title3,design:.monospaced)).foregroundStyle(mint); VStack(alignment:.leading,spacing:8) { Text(heading).font(.headline); Text(body).foregroundStyle(.secondary) } }
    }
    private var outbox: some View {
        VStack(alignment:.leading,spacing:18) {
            title("MessageBox outbox", "Encrypted delivery records survive restarts. Recovery uses the saved payment; it cannot start a second one.")
            action("My delivery wallet key","wallet.pass") { model.identity(root:true) }
            if let records = try? model.store.list() {
                if records.isEmpty { Text("No deliveries yet. Encrypt a v2 message and choose Send with MessageBox.").foregroundStyle(.secondary) }
                ForEach(records.indices,id:\.self) { i in
                    let r = records[i]
                    action((r["name"] as? String ?? "Recipient") + " · " + (r["state"] as? String ?? "Unknown"),"envelope") { model.showDelivery(r["id"] as? String ?? "") }
                }
            } else { Text("Some saved records could not be read. They have been retained; do not create another payment for an uncertain delivery.").foregroundStyle(.orange) }
            back()
        }
    }
    @ViewBuilder private var delivery: some View {
        if let r = try? model.store.get(model.deliveryID), let state = r["state"] as? String {
            if DeliveryStore.discarded(r) {
                title("Sent · cleanup pending","The message was accepted. Only a cleanup marker remains; no new payment is allowed.")
                action("Retry local cleanup",primary:true) { model.deliver("cleanup") }; back(.outbox)
            } else {
            title("MessageBox delivery",state.replacingOccurrences(of:"_",with:" "))
            Text("To: " + (r["name"] as? String ?? "Recipient"))
            Text(model.store.serviceHost + "\nInbox: notifications").font(.footnote).foregroundStyle(.secondary)
            if let key = r["encryptionKey"] as? String, key != "self" { Text("Crypton receiving key").font(.caption); selectable(key) }
            if ["DRAFT","QUOTED"].contains(state) {
                Text("MessageBox delivers to a wallet identity. It can differ from the Crypton receiving key used to encrypt this message.").font(.footnote).foregroundStyle(.secondary)
                textField("Recipient wallet identity (blank for self)",$model.deliveryRecipient,key:true)
                if let p = r["prepared"] as? JSON, let q = p["quote"] as? JSON, let fee = try? model.store.feeTotal(q) {
                    Text("Server: \(integer(q["deliveryFee"]) ?? 0) sats\nRecipient: \(integer(q["recipientFee"]) ?? 0) sats\nMessageBox fees: \(fee) sats").font(.headline)
                    Text("Your wallet may add storage and network fees. Review the full total in its transaction prompt before approving.").font(.footnote).foregroundStyle(.secondary)
                    action(fee == 0 ? "Send message" : "Review payment in wallet and send","paperplane",primary:true) { model.deliver("send") }
                }
                action(state == "DRAFT" ? "Check delivery fee" : "Refresh delivery fee","arrow.clockwise") { model.deliver("prepare") }
            } else if state == "SENT" {
                Label("Accepted by MessageBox",systemImage:"checkmark.circle").foregroundStyle(mint)
                Text("Acceptance confirms server delivery, not that the recipient has opened your message.").font(.footnote).foregroundStyle(.secondary)
                if let receipt = r["receipt"] as? JSON { selectable(receipt["messageId"] as? String ?? "") }
            } else if state == "PAYMENT_REQUESTED" {
                Text("The payment outcome is uncertain. Check the wallet history. A second payment is blocked.").foregroundStyle(.orange)
                action("Check wallet history","clock") { model.deliver("recover") }
                if let history = r["walletHistory"] { selectable((try? jsonString(history)) ?? "") }
            } else { action("Retry delivery with saved payment","arrow.clockwise",primary:true) { model.deliver("resume") } }
            if let payment = r["payment"] as? JSON { Text("Payment transaction").font(.caption); selectable(payment["txid"] as? String ?? "") }
            if let error = r["error"] as? String { Text(error).foregroundStyle(.orange) }
            if r["disappear"] as? Bool != true { action("Share encrypted payload","square.and.arrow.up") { modal = .share(SharedItems(items:[r["envelope"] as? String ?? ""])) } }
            back(.outbox)
            }
        } else { title("Delivery unavailable","The saved record has been retained."); back(.outbox) }
    }
    private var inbox:some View {
        VStack(alignment:.leading,spacing:18) {
            title("MessageBox inbox","Refresh to retrieve encrypted messages through your selected wallet. No payments are accepted automatically.")
            action("Refresh inbox","arrow.clockwise",primary:true) { model.receive("refresh") }
            if !model.inboxWallet.isEmpty { Text("Saved wallet: " + model.inboxWallet.prefix(14) + "… · refresh to use ME’s current profile").font(.footnote).foregroundStyle(.secondary) }
            if !model.inboxNotice.isEmpty { Text(model.inboxNotice).accessibilityIdentifier("inboxNotice") }
            Toggle("Show dismissed messages",isOn:$model.showDismissed).tint(mint)
            ForEach(model.inboxRows.indices,id:\.self) { index in
                let r = model.inboxRows[index], id = r["messageId"] as? String ?? ""
                let state = InboxStore.pending(r) ? "Server removal pending" : r["dismissed"] as? Bool == true ? "Dismissed" : r["read"] as? Bool == true ? "Read" : "Unread"
                action(state + " · " + id.prefix(8),"envelope") { model.showInboxMessage(id) }.accessibilityIdentifier("inbox-"+id)
            }
            if model.inboxRows.isEmpty { Text("No saved Crypton messages in this view.").foregroundStyle(.secondary) }
            if model.inboxMore { action("Load more messages","arrow.down") { model.receive("refresh",more:true) } }
            back()
        }
    }
    @ViewBuilder private var inboxMessage:some View {
        title("Received message")
        if let content = model.inboxContent {
            let layer = content["kind"] as? String == "layer", text = content[layer ? "note" : "text"] as? String ?? ""
            if model.privateInboxView { Text(text).accessibilityIdentifier("inboxPlaintext") }
            else { Text(text).textSelection(.enabled).accessibilityIdentifier("inboxPlaintext") }
            if model.privateInboxView {
                Text(model.privateRemoved ? "Server removal confirmed · no saved message copy" : "Server removal pending · retry continues after you close this view")
                if layer { action("Open inner layer",primary:true) { model.receive("layer") } }
                if !model.privateRemoved { action("Retry server removal") { model.receive("remove") } }
                action("Close message","checkmark",primary:true) { model.closeInboxMessage() }
            } else {
                if layer { action("Open inner layer",primary:true) { _ = model.importMessage(content["envelope"] as? String ?? "") } }
                else {
                    action("Copy text","doc.on.doc") { model.copyText(text) }
                    action("Share text","square.and.arrow.up") { modal = .share(SharedItems(items:[text])) }
                }
            }
        }
        if !model.privateInboxView, let r = try? model.inboxStore.get(model.inboxWallet,model.inboxID) {
            if InboxStore.pending(r) {
                Text("Server removal pending. The saved message copy has been removed.")
                action("Retry server removal",primary:true) { model.receive("remove") }
            } else {
                if model.inboxContent == nil { action(model.disappearReceive ? "Decrypt once and remove" : "Decrypt message","lock.open",primary:true) { model.receive("open") } }
                DisclosureGroup("Delivery details") {
                    selectable(r["sender"] as? String ?? ""); selectable(model.inboxID)
                }
                action(r["dismissed"] as? Bool == true ? "Restore message" : "Dismiss on this device","archivebox") { model.flagInbox(r["dismissed"] as? Bool != true) }
            }
        }
        if !model.privateInboxView { action("Back to inbox") { model.closeInboxMessage() } }
    }
    private func received(_ value:Result<String,Error>) {
        modal = nil
        switch value {
        case .success(let text):
            if scanIdentity { do { model.keyDraft = try Wire.identity(text) } catch { model.error = error.localizedDescription } }
            else { model.importMessage(text) }
        case .failure(let error): model.error = error.localizedDescription
        }
    }
    private func export(_ contact:PublicContact) {
        do {
            let c = CNMutableContact(); c.givenName = contact.name; c.urlAddresses = [CNLabeledValue(label:"Crypton",value:contact.key as NSString)]
            let data = try CNContactVCardSerialization.data(with:[c])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("crypton-contact.vcf")
            try data.write(to:url,options:[.atomic,.completeFileProtection]); modal = .share(SharedItems(items:[url]))
        } catch { model.error = error.localizedDescription }
    }
}
