#if targetEnvironment(simulator)
import Foundation
import CryptoKit

/// Opt-in simulator control. No URL handler, wallet credential or spending bypass.
@MainActor final class ScriptedRun {
    private unowned let model: AppModel
    private let plan: JSON
    private let folder: URL
    private let role: String
    private let began = ProcessInfo.processInfo.systemUptime
    private var started = false
    private var attemptedSend = false
    private var sendingAfter = Double.infinity
    private var task: Task<Void,Never>?
    init?(model:AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of:"--crypton-script"), args.indices.contains(index+1),
              let id = UUID(uuidString:args[index+1]) else { return nil }
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScriptedRuns")
        let folder = root.appendingPathComponent(id.uuidString.lowercased(),isDirectory:true)
        let request = folder.appendingPathComponent("request.json")
        guard let bytes = try? Data(contentsOf:request) else { return nil }
        try? FileManager.default.removeItem(at:request)
        guard bytes.count <= 100_000, let value = try? object(bytes), value["run_id"] as? String == id.uuidString.lowercased(),
              let role = value["role"] as? String, ["preflight","send","receive"].contains(role) else { return nil }
        self.model = model; self.folder = folder; self.plan = value; self.role = role
    }
    private func event(_ stage:String,_ fields:JSON = [:]) {
        let clock = ISO8601DateFormatter(); clock.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        var e:JSON = ["run_id":plan["run_id"]!,"role":role,"stage":stage,"utc":clock.string(from:Date()),"elapsed_ms":(ProcessInfo.processInfo.systemUptime-began)*1000]
        fields.forEach { e[$0.key] = $0.value }
        guard var data = try? jsonData(e) else { return }; data.append(10)
        let file = folder.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:file) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf:data); try? handle.synchronize() }
    }
    private func require(_ value:Bool,_ message:String) throws { if !value { throw CryptonError(message) } }
    private func settle() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + (plan["timeout"] as? Double ?? 300)
        var progress = ""
        while model.busy {
            if model.activity != progress { progress = model.activity; event("progress",["detail":progress]) }
            try require(ProcessInfo.processInfo.systemUptime < deadline,"Script phase timed out. Inspect the saved payment; do not repeat Send.")
            try await Task.sleep(nanoseconds:50_000_000)
        }
        if let error = model.error { throw CryptonError(error) }
    }
    private func claimSend() async throws {
        try require(plan["mode"] as? String != "verify_only","Verification cannot send")
        guard let address = plan["claim_url"] as? String, let url = URL(string:address), url.host == "127.0.0.1", url.path == "/claim",
              let token = plan["claim_token"] as? String else { throw CryptonError("Missing single-use send claim") }
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization"); request.setValue(plan["run_id"] as? String,forHTTPHeaderField:"X-Crypton-Run")
        let (_,response) = try await URLSession.shared.data(for:request)
        try require((response as? HTTPURLResponse)?.statusCode == 200,"Send claim was refused; inspect the original run before retrying")
    }
    func start() {
        guard !started else { return }; started = true
        task = Task { [self] in
            do {
                event("started"); model.screen = .home; event("app_ready")
                try require(!model.legacy && !model.disappearSend && !model.disappearReceive,"Scripted runs require Crypton v2 and retained sent/received copies")
                let fixture = plan["fixture"] as? Bool == true
                try require(model.walletMode == (fixture ? "json" : "me"),"The configured wallet mode does not match this run")
                event("settings_verified")
                if role == "preflight" { event("preflight_complete"); event("phase_complete"); return }
                guard let text = plan["message"] as? String else { throw CryptonError("Missing scripted text") }
                if role == "send" {
                    if fixture { model.choose("self") }
                    else {
                        let card:JSON = ["protocol":"crypton-contact","version":1,"name":plan["recipient_name"]!,"receivingKey":plan["receiving_key"]!,"walletIdentity":plan["wallet_identity"]!]
                        model.choose(String(decoding:try jsonData(card),as:UTF8.self))
                        try require(model.recipientWalletDraft == plan["wallet_identity"] as? String,"Recipient contact did not match the request")
                    }
                    try require(model.screen == .compose,"Recipient was not accepted")
                    model.message = text; event("composed"); try await claimSend()
                    sendingAfter = Date().timeIntervalSince1970 * 1000
                    attemptedSend = true; event("send_tapped"); model.process(sendWithMessageBox:true); try await settle()
                    let record = try model.store.get(model.deliveryID)
                    try require(record["state"] as? String == "SENT","Native delivery did not reach SENT; inspect the saved payment")
                    guard let id = (record["receipt"] as? JSON)?["messageId"] as? String else { throw CryptonError("Missing acceptance receipt") }
                    event("accepted",["message_id":id]); event("phase_complete"); return
                }
                guard let id = plan["message_id"] as? String else { throw CryptonError("Missing message ID") }
                _ = try InboxStore.messageID(id)
                model.showInbox()
                var found = false
                for attempt in 0..<10 {
                    event(attempt == 0 ? "refresh_tapped" : "refresh_retry",["attempt":attempt])
                    model.receive("refresh"); try await settle()
                    if model.inboxRows.contains(where:{$0["messageId"] as? String == id}) { found = true; break }
                    try await Task.sleep(nanoseconds:1_000_000_000)
                }
                try require(found,"The exact message was not present after completed inbox reads")
                event("received",["message_id":id]); model.showInboxMessage(id)
                event("decrypt_tapped"); model.receive("open"); try await settle()
                try require(model.inboxContent?["text"] as? String == text,"Decrypted plaintext does not match the original run")
                event("decrypted",["text_sha256":SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()])
                model.closeInboxMessage(); model.showInboxMessage(id)
                let saved = try model.inboxStore.get(model.inboxWallet,id)
                try require(saved["read"] as? Bool == true && !InboxStore.pending(saved),"The read message was not retained")
                event("retained",["message_id":id]); event("phase_complete")
            } catch {
                var fields:JSON = ["reason":error.localizedDescription,"send_attempted":attemptedSend]
                if role == "send", attemptedSend, !model.busy,
                   let record = try? model.store.get(model.deliveryID),
                   let created = record["created"] as? Double, created >= sendingAfter {
                    fields["delivery_id"] = model.deliveryID; fields["delivery_state"] = record["state"]
                    if DeliveryStore.paymentNeverRequested(record) { fields["payment_not_requested"] = true }
                }
                event("failed",fields)
            }
        }
    }
}
#endif
