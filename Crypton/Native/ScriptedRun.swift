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
    private var announcedPayment = false
    private var task: Task<Void,Never>?
    private(set) var finished = false
    init?(model:AppModel,id supplied:UUID? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let id:UUID
        if let supplied = supplied { id = supplied }
        else {
            guard let index = args.firstIndex(of:"--crypton-script"), args.indices.contains(index+1),
                  let parsed = UUID(uuidString:args[index+1]) else { return nil }; id = parsed
        }
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScriptedRuns")
        let folder = root.appendingPathComponent(id.uuidString.lowercased(),isDirectory:true)
        let request = folder.appendingPathComponent("request.json")
        guard let bytes = try? Data(contentsOf:request) else { return nil }
        try? FileManager.default.removeItem(at:request)
        guard bytes.count <= 100_000, let value = try? object(bytes), value["run_id"] as? String == id.uuidString.lowercased(),
              let role = value["role"] as? String, ["preflight","send","receive","reopen","recover-review"].contains(role) else { return nil }
        self.model = model; self.folder = folder; self.plan = value; self.role = role
    }
    private func event(_ stage:String,_ fields:JSON = [:]) {
        let clock = ISO8601DateFormatter(); clock.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        var e:JSON = ["run_id":plan["run_id"]!,"role":role,"stage":stage,"utc":clock.string(from:Date()),"elapsed_ms":(ProcessInfo.processInfo.systemUptime-began)*1000,"mono_ms":ProcessInfo.processInfo.systemUptime*1000]
        fields.forEach { e[$0.key] = $0.value }
        guard var data = try? jsonData(e) else { return }; data.append(10)
        let file = folder.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:file) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf:data); if ["phase_complete","failed"].contains(stage) { try? handle.synchronize() } }
    }
    private func require(_ value:Bool,_ message:String) throws { if !value { throw CryptonError(message) } }
    private func settle() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + (plan["timeout"] as? Double ?? 300)
        var progress = ""
        while model.busy {
            if model.activity != progress { progress = model.activity; event("progress",["detail":progress]) }
            if role == "send", attemptedSend, !announcedPayment,
               let record = try? model.store.get(model.deliveryID), let created = record["created"] as? Double, created >= sendingAfter,
               ["PAID","SUBMITTING","SENT"].contains(record["state"] as? String ?? ""), record["payment"] is JSON,
               let prepared = record["prepared"] as? JSON, let messageID = prepared["messageId"] as? String,
               (try? InboxStore.messageID(messageID)) != nil {
                announcedPayment = true
                event("payment_saved",["delivery_id":model.deliveryID,"message_id":messageID,"has_saved_payment":true])
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                // Do not leave the engine able to reach payment after the CLI has
                // stopped recording. Cancellation preserves every payment marker.
                model.cancel()
                let settleDeadline = ProcessInfo.processInfo.systemUptime + 2
                while model.busy && ProcessInfo.processInfo.systemUptime < settleDeadline {
                    try await Task.sleep(nanoseconds:10_000_000)
                }
                throw CryptonError("Script phase timed out and was cancelled. Inspect the saved outcome before retrying.")
            }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        if let error = model.error { throw CryptonError(error) }
    }
    private func claimSend() async throws {
        try require(plan["mode"] as? String == "send","This mode cannot send")
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
            defer { model.scriptedExpectedSender = nil; model.scriptedEvent = nil; finished = true; model.publishScriptRuntime() }
            do {
                event("started",["runtime_id":model.scriptedRuntimeID,"engine_id":model.scriptedEngineID ?? "","pid":ProcessInfo.processInfo.processIdentifier])
                if plan["launch_kind"] as? String == "warm" {
                    try require(plan["expected_runtime_id"] as? String == model.scriptedRuntimeID &&
                                !(model.scriptedEngineID ?? "").isEmpty && plan["expected_engine_id"] as? String == model.scriptedEngineID,
                                "Warm run requires the same existing Crypton process and crypto engine; no Send was attempted")
                }
                model.screen = .home; event("app_ready")
                try require(!model.legacy && !model.disappearSend && !model.disappearReceive,"Scripted runs require Crypton v2 and retained sent/received copies")
                let fixture = plan["fixture"] as? Bool == true
                try require(model.walletMode == (fixture ? "json" : "me"),"The configured wallet mode does not match this run")
                event("settings_verified")
                if role == "preflight" {
                    if plan["verify_profile"] as? Bool == true {
                        model.identity(); try await settle()
                        try require(model.sharedIdentity?.key == plan["receiving_key"] as? String && model.sharedIdentity?.walletIdentity == plan["wallet_identity"] as? String,"Receiver wallet profile changed")
                        event("profile_verified")
                    }
                    event("preflight_complete"); event("phase_complete"); return
                }
                if role == "recover-review" {
                    try require(plan["mode"] as? String == "recover_review","Recovery mode is required")
                    guard let id = plan["delivery_id"] as? String, UUID(uuidString:id) != nil,
                          let sender = plan["sender_identity"] as? String else { throw CryptonError("Missing exact recovery target") }
                    let record = try model.store.get(id)
                    try require(record["state"] as? String == "PAYMENT_REQUESTED" &&
                                (record["walletRefusal"] as? JSON)?["notCommitted"] as? Bool == true &&
                                (record["prepared"] as? JSON)?["sender"] as? String == sender &&
                                record["payment"] == nil && record["walletResult"] == nil,
                                "Recovery requires the exact wallet's definite uncommitted refusal")
                    model.showDelivery(id)
                    model.deliver("recover"); try await settle()
                    let checked = try model.store.get(id)
                    guard let history = checked["walletHistory"] as? JSON,
                          history["sender"] as? String == sender,
                          integer(history["totalActions"]) == 0,
                          let transactions = history["transactions"] as? [JSON], transactions.isEmpty else {
                        throw CryptonError("Wallet history did not prove the refused review was unpaid")
                    }
                    // The store also checks history freshness and every payment marker.
                    model.deliver("retryRefused"); try await settle()
                    let resolved = try model.store.get(id)
                    try require(resolved["state"] as? String == "DRAFT" &&
                                (resolved["previousRefusal"] as? JSON)?["notCommitted"] as? Bool == true,
                                "Refused review remains protected")
                    event("unpaid_review_recovered",["delivery_id":id,"sender_identity":sender,"total_actions":0,"delivery_state":"DRAFT"])
                    event("phase_complete"); return
                }
                guard let text = plan["message"] as? String else { throw CryptonError("Missing scripted text") }
                if role == "send" {
                    if !fixture { model.scriptedExpectedSender = try Wire.identity(plan["sender_identity"] as? String ?? "") }
                    var identityReported = false
                    model.scriptedEvent = { [weak self] stage in
                        if stage == "sender_verified" { if identityReported { return }; identityReported = true }
                        self?.event(stage)
                    }
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
                if (!fixture || role == "reopen"), let receivingWallet = plan["wallet_identity"] as? String { model.inboxWallet = try Wire.identity(receivingWallet) }
                if role == "reopen" {
                    model.showInboxMessage(id); event("decrypt_tapped")
                    model.receive("open"); try await settle()
                    try require(model.inboxContent?["text"] as? String == text,"Reopened plaintext does not match the original run")
                    event("decrypted")
                    let saved = try model.inboxStore.get(model.inboxWallet,id)
                    try require(saved["read"] as? Bool == true && !InboxStore.pending(saved),"Restart lost the retained message")
                    event("retained",["message_id":id]); event("phase_complete"); return
                }
                var found = false, more = false
                for attempt in 0..<10 {
                    event(attempt == 0 ? "refresh_tapped" : "refresh_retry",["attempt":attempt])
                    model.inboxID = id; model.receive("verify",more:more); try await settle()
                    if model.inboxContent != nil { found = true; break }
                    more = model.inboxMore
                    if !more { try await Task.sleep(nanoseconds:1_000_000_000) }
                }
                try require(found,"The exact message was not present after completed inbox reads")
                event("received",["message_id":id]) // The explicit verify action already opened this exact ID.
                event("verification_completed",["message_id":id])
                try require(model.inboxContent?["text"] as? String == text,"Decrypted plaintext does not match the original run")
                event("decrypted",["text_sha256":SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()])
                model.closeInboxMessage(); model.showInboxMessage(id)
                let saved = try model.inboxStore.get(model.inboxWallet,id)
                try require(saved["read"] as? Bool == true && !InboxStore.pending(saved),"The read message was not retained")
                event("retained",["message_id":id,"wallet_identity":model.inboxWallet]); event("phase_complete")
            } catch {
                var fields:JSON = ["reason":error.localizedDescription,"send_attempted":attemptedSend]
                if role == "send", attemptedSend, !model.busy,
                   let record = try? model.store.get(model.deliveryID),
                   let created = record["created"] as? Double, created >= sendingAfter {
                    fields["delivery_id"] = model.deliveryID; fields["delivery_state"] = record["state"]
                    if DeliveryStore.paymentNeverRequested(record) { fields["payment_not_requested"] = true }
                    if record["state"] as? String == "SUBMITTING", record["payment"] is JSON,
                       let prepared = record["prepared"] as? JSON, let messageID = prepared["messageId"] as? String,
                       (try? InboxStore.messageID(messageID)) != nil {
                        fields["has_saved_payment"] = true; fields["message_id"] = messageID
                    }
                }
                event("failed",fields)
            }
        }
    }
}
#endif
