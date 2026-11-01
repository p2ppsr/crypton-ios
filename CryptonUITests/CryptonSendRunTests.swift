import XCTest
import CryptoKit
import Darwin

/// Opt-in, parameterized automation. Never taps a wallet Pay/Allow button.
final class CryptonSendRunTests: XCTestCase {
    private var plan: [String:Any] = [:]
    private var sendAttempted = false
    private var began = ProcessInfo.processInfo.systemUptime
    private let app = XCUIApplication(bundleIdentifier:"com.projectbabbage.Crypton")
    private let me = XCUIApplication(bundleIdentifier:"app.metanet.explorer")
    private var role: String { plan["role"] as? String ?? "unknown" }
    private var fixture: Bool { plan["fixture"] as? Bool == true }
    private var timeout: TimeInterval { plan["timeout"] as? Double ?? 300 }
    private func event(_ stage:String,_ fields:[String:Any] = [:]) {
        let clock = ISO8601DateFormatter(); clock.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        var value:[String:Any] = ["run_id":plan["run_id"] ?? "", "role":role, "stage":stage,
            "utc":clock.string(from:Date()),"elapsed_ms":(ProcessInfo.processInfo.systemUptime-began)*1000]
        for (key,v) in fields { value[key] = v }
        let bytes = try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])
        print("CRYPTON_RUN_EVENT " + String(decoding:bytes,as:UTF8.self)); fflush(stdout)
    }
    private func require(_ condition:Bool,_ message:String) throws {
        if !condition { event("failed",["reason":message,"send_attempted":sendAttempted]); throw NSError(domain:"CryptonSendRun",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    private func button(_ name:String) throws -> XCUIElement {
        let b = app.buttons[name]; try require(b.waitForExistence(timeout:10),"Missing Crypton control: " + name)
        for _ in 0..<5 where !b.isHittable { app.swipeUp() }
        try require(b.isHittable,"Crypton control is not reachable: " + name); return b
    }
    private func launch() throws {
        app.launchArguments = fixture ? ["--uitesting","--sdk-wallet-fixture","--messagebox-fixture"] : []
        app.launch()
        try require(app.buttons["Crypton home"].waitForExistence(timeout:15),"Crypton did not launch")
        app.buttons["Crypton home"].tap()
        event("app_ready")
    }
    private func checkSettings() throws {
        try button("Settings").tap()
        for id in ["legacyMessages","disappearSent","disappearReceived"] {
            let toggle = app.switches[id]
            for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
            try require(toggle.exists && (toggle.value as? String) == "0","Set " + id + " off before running; this script does not change settings")
        }
        let picker = app.buttons["walletConnection"]
        for _ in 0..<6 where !picker.isHittable { app.swipeDown() }
        let wanted = fixture ? "BRC-100 JSON" : "Metanet Explorer"
        let actual = picker.label + " " + (picker.value as? String ?? "")
        try require(actual.contains(wanted),"Select " + wanted + " before running")
        try button("Crypton home").tap(); event("settings_verified")
    }
    private func fill(_ field:XCUIElement,_ text:String) throws {
        try require(field.waitForExistence(timeout:10),"Message input is missing")
        field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty { field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.utf16.count)) }
        field.typeText(text)
        try require((field.value as? String) == text,"Input differs from the requested text; send was not attempted")
        for id in ["messageInputDone","keyInputDone"] {
            let done = app.buttons[id]
            if done.exists && done.isHittable { done.tap(); break }
        }
    }
    private func waitForOutcome(_ condition:()->Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date()<deadline {
            if condition() { return }
            if app.state == .runningForeground && app.alerts.firstMatch.exists {
                event("app_error",["detail":app.alerts.firstMatch.label])
                throw NSError(domain:"CryptonSendRun",code:2,userInfo:[NSLocalizedDescriptionKey:"Crypton displayed an error; inspect the saved recording and recovery record"])
            }
            Thread.sleep(forTimeInterval:0.2)
        }
        event("timed_out")
        throw NSError(domain:"CryptonSendRun",code:3,userInfo:[NSLocalizedDescriptionKey:"Run timed out; never repeat a payment automatically"])
    }
    private func claimSend() throws {
        guard let address = plan["claim_url"] as? String,let url = URL(string:address), url.host == "127.0.0.1", url.path == "/claim",
              let token = plan["claim_token"] as? String else { try require(false,"Missing single-use send authorization"); return }
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 5
        request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
        request.setValue(plan["run_id"] as? String,forHTTPHeaderField:"X-Crypton-Run")
        let semaphore = DispatchSemaphore(value:0)
        var status = 0
        URLSession.shared.dataTask(with:request) { _,response,_ in status = (response as? HTTPURLResponse)?.statusCode ?? 0; semaphore.signal() }.resume()
        let finished = semaphore.wait(timeout:.now()+6) == .success
        // A lost claim response is uncertain too. Do not grant a second claim.
        try require(finished && status == 200,"Single-use Send was not authorized; inspect this run before retrying")
    }
    @MainActor func testDeterministicMessageFlow() throws {
        continueAfterFailure = false
        guard let encoded = ProcessInfo.processInfo.environment["CRYPTON_SEND_PLAN"],let bytes = Data(base64Encoded:encoded),
              let decoded = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw XCTSkip("Use scripts/send-message.py to opt in") }
        plan = decoded; began = ProcessInfo.processInfo.systemUptime
        if role == "send" {
            let marker = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("crypton-send-" + (plan["run_id"] as! String))
            sendAttempted = FileManager.default.fileExists(atPath:marker.path)
            try require(!sendAttempted,"This run already attempted Send; automatic replay is blocked")
        }
        event("started"); try launch(); try checkSettings()
        if role == "preflight" { event("preflight_complete"); return }
        let text = plan["message"] as! String
        if role == "send" {
            try button("New message").tap()
            if fixture { try button("Myself").tap() }
            else {
                let contact:[String:Any] = ["protocol":"crypton-contact","version":1,"name":plan["recipient_name"]!,"receivingKey":plan["receiving_key"]!,"walletIdentity":plan["wallet_identity"]!]
                let card = String(decoding:try JSONSerialization.data(withJSONObject:contact,options:[.sortedKeys]),as:UTF8.self)
                try fill(app.textViews["Identity public key"],card); try button("Continue").tap()
                try require((app.textViews["Recipient delivery wallet key"].value as? String) == (plan["wallet_identity"] as? String),"Contact did not fill the expected delivery identity")
            }
            try fill(app.textViews["messageEditor"],text); event("composed")
            let send = try button("Send with MessageBox")
            let marker = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("crypton-send-" + (plan["run_id"] as! String))
            try claimSend()
            let fd = open(marker.path,O_WRONLY | O_CREAT | O_EXCL,0o600)
            try require(fd >= 0,"This run's send marker already exists; replay is blocked")
            close(fd); sendAttempted = true
            event("send_tapped"); send.tap()
            var sawPay = false
            try waitForOutcome {
                if me.state == .runningForeground {
                    let pay = me.buttons["p0-spending-spend"]
                    if pay.exists && pay.isEnabled && pay.label.hasPrefix("Pay ") && !sawPay {
                        sawPay = true; self.event("pay_visible",["label":pay.label])
                        // Human-only final payment action. No Pay/Allow selector is ever tapped.
                    }
                }
                return self.app.state == .runningForeground && self.app.staticTexts["Accepted by MessageBox"].exists
            }
            let id = app.staticTexts["deliveryMessageID"].label
            try require(id.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,"Acceptance has no valid message ID")
            event("accepted",["message_id":id]); return
        }
        try require(role == "receive","Unknown automation phase")
        let id = plan["message_id"] as! String
        try button("MessageBox inbox").tap()
        event("refresh_tapped"); try button("Refresh inbox").tap()
        let row = app.buttons["inbox-"+id]
        var lastRefresh = Date(), refreshes = 0
        try waitForOutcome {
            guard self.app.state == .runningForeground else { return false }
            if row.exists { return true }
            // A fresh accepted message can lag the first inbox read. Retry only
            // completed read operations; never foreground Crypton over ME.
            if self.app.buttons["walletStatus"].label == "Inbox up to date" && Date().timeIntervalSince(lastRefresh) >= 2 && refreshes < 10 {
                refreshes += 1; lastRefresh = Date()
                self.event("refresh_retry",["attempt":refreshes])
                self.app.buttons["Refresh inbox"].tap()
            }
            return false
        }
        event("received",["message_id":id]); row.tap()
        event("decrypt_tapped"); try button("Decrypt message").tap()
        let plaintext = app.staticTexts["inboxPlaintext"]
        try waitForOutcome { self.app.state == .runningForeground && plaintext.exists }
        try require(plaintext.label == text,"Recipient plaintext does not match the exact requested message")
        event("decrypted",["text_sha256":SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()])
        try button("Back to inbox").tap(); try require(row.waitForExistence(timeout:10),"Received message was not retained")
        row.tap(); try require(app.buttons["Decrypt message"].waitForExistence(timeout:10),"Retained ciphertext cannot be reopened")
        event("retained",["message_id":id])
    }
}
