import XCTest

final class CryptonUITests: XCTestCase {
    @MainActor func testRecipientSearchSelectSaveEncryptAndDeliveryPrefill() async throws {
        let recipient:[String:Any]
        do { recipient = try await fixture("recipient") } catch { throw XCTSkip("Start the disposable SDK fixture") }
        let statsBefore = try await fixture("discovery-stats")
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture","--messagebox-fixture","--reset-qa-outbox"]; app.launch()
        app.buttons["New message"].tap()
        let query = app.textFields["recipientSearchQuery"].exists ? app.textFields["recipientSearchQuery"] : app.textViews["recipientSearchQuery"]
        query.tap(); query.typeText("bob@example.com")
        let statsTyped = try await fixture("discovery-stats")
        XCTAssertEqual(statsTyped["requests"] as? Int,statsBefore["requests"] as? Int,"Typing alone must not query the wallet")
        app.swipeUp(); app.buttons["Search"].tap()
        let select = app.buttons["selectRecipient-" + (recipient["publicKey"] as! String)]
        XCTAssertTrue(select.waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["Write a secret."].exists,"Require explicit selection")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Certified recipient search results (disposable fixture)"; shot.lifetime = .keepAlways; add(shot)
        select.tap()
        XCTAssertTrue(app.buttons["Save recipient contact"].waitForExistence(timeout:5)); app.buttons["Save recipient contact"].tap()
        XCTAssertTrue(app.buttons["Recipient saved"].exists)
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText("Sent to the selected certified identity")
        app.swipeUp(); app.buttons["Encrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Sealed and ready."].waitForExistence(timeout:15))
        let envelope = app.staticTexts["resultText"].label
        let opened = try await fixture("v2-open",["envelope":envelope])
        XCTAssertEqual(opened["text"] as? String,"Sent to the selected certified identity")
        app.swipeUp(); app.buttons["Send with MessageBox"].tap()
        let walletKey = app.textFields["Recipient wallet identity (blank for self)"].exists ? app.textFields["Recipient wallet identity (blank for self)"] : app.textViews["Recipient wallet identity (blank for self)"]
        XCTAssertTrue(walletKey.waitForExistence(timeout:5)); XCTAssertEqual(walletKey.value as? String,recipient["publicKey"] as? String)
        app.buttons["Crypton home"].tap(); app.buttons["Contacts"].tap()
        XCTAssertTrue(app.buttons["bob@example.com"].exists)
    }
    @MainActor func testRecipientSearchEmptyAndEditingClearsResults() async throws {
        do { _ = try await fixture("recipient") } catch { throw XCTSkip("Start the disposable SDK fixture") }
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["New message"].tap()
        let query = app.textFields["recipientSearchQuery"].exists ? app.textFields["recipientSearchQuery"] : app.textViews["recipientSearchQuery"]
        query.tap(); query.typeText("empty@example.com"); app.swipeUp(); app.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["recipientSearchSummary"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["recipientSearchSummary"].label.contains("No matching identities"))
        app.swipeDown(); query.tap(); query.typeText("x")
        XCTAssertFalse(app.staticTexts["recipientSearchSummary"].exists)
        XCTAssertFalse(app.buttons["Use this recipient"].exists)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    func app() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch(); return app
    }
    func testHomeComposeAndLegacySenderSelection() {
        let app = app()
        app.buttons["New message"].tap()
        XCTAssertTrue(app.staticTexts["Choose recipient"].exists)
        app.buttons["Myself"].tap()
        XCTAssertTrue(app.textViews["messageEditor"].exists)
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText("A private draft")
        app.buttons["Crypton home"].tap()
        app.buttons["Decrypt message"].tap()
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText("QUFBQQ==")
        app.swipeUp(); app.buttons["Decrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Choose sender"].exists)
    }
    func testContactsAndSettings() {
        let app = app()
        app.buttons["Contacts"].tap()
        let name = app.textFields["Contact name"].exists ? app.textFields["Contact name"] : app.textViews["Contact name"]
        name.tap(); name.typeText("Test friend")
        let key = app.textFields["Identity public key"].exists ? app.textFields["Identity public key"] : app.textViews["Identity public key"]
        key.tap(); key.typeText("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
        app.swipeUp(); app.buttons["Save contact"].tap()
        app.swipeDown(); XCTAssertTrue(app.buttons["Test friend"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings."].exists)
        XCTAssertTrue(app.switches["Legacy iPhone message format"].exists)
    }
    @MainActor func testShareExtensionTextRoundTrip() async throws { try await shareRoundTrip(image:false) }
    @MainActor func testShareExtensionImageRoundTrip() async throws { try await shareRoundTrip(image:true) }
    @MainActor func testFilesTextExportImportRoundTrip() async throws { try await filesRoundTrip(image:false) }
    @MainActor func testFilesQRExportImportRoundTrip() async throws { try await filesRoundTrip(image:true) }
    @MainActor func testPhotoExportAndIdentityPhotoImport() async throws {
        do { _ = try await fixture("recipient") } catch { throw XCTSkip("Start the disposable SDK fixture") }
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["My identity"].tap()
        guard app.staticTexts["resultText"].waitForExistence(timeout:15) else { XCTFail("Identity unavailable"); return }
        let identity = app.staticTexts["resultText"].label
        app.buttons["Share QR image"].tap()
        let saveImage = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Save Image")).firstMatch
        guard saveImage.waitForExistence(timeout:8) else { XCTFail("Save Image missing: " + app.debugDescription); return }
        saveImage.tap()
        let system = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if system.alerts.firstMatch.waitForExistence(timeout:3) {
            let allow = system.alerts.firstMatch.buttons["Allow"]
            guard system.alerts.firstMatch.label.contains("Would Like to Add to Your Photos"), allow.exists else { XCTFail("Unexpected photo permission prompt: " + system.debugDescription); return }
            allow.tap()
        }
        app.buttons["Crypton home"].tap(); app.buttons["Contacts"].tap(); app.buttons["QR image"].tap()
        let photo = app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        guard photo.waitForExistence(timeout:10) else { XCTFail("Photo grid missing: " + app.debugDescription); return }; photo.tap()
        let key = app.textFields["Identity public key"].exists ? app.textFields["Identity public key"] : app.textViews["Identity public key"]
        XCTAssertTrue(key.waitForExistence(timeout:8)); XCTAssertEqual(key.value as? String,identity)
    }
    @MainActor func testHEICIdentityPhotoImport() async throws {
        do {
            guard try await fixture("qa-config")["heicReady"] as? Bool == true else { throw XCTSkip("Run scripts/test-ios.sh with CRYPTON_SDK_ROOT to seed the HEIC fixture") }
        } catch { throw XCTSkip("Run scripts/test-ios.sh with CRYPTON_SDK_ROOT to seed the HEIC fixture") }
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["Contacts"].tap(); app.buttons["QR image"].tap()
        let photo = app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        guard photo.waitForExistence(timeout:10) else { XCTFail("HEIC photo fixture missing"); return }; photo.tap()
        let key = app.textFields["Identity public key"].exists ? app.textFields["Identity public key"] : app.textViews["Identity public key"]
        let expected = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        await fulfillment(of:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",expected),object:key)],timeout:10)
        XCTAssertEqual(key.value as? String,expected)
    }
    @MainActor private func filesRoundTrip(image:Bool) async throws {
        do { _ = try await fixture("recipient") } catch { throw XCTSkip("Start the disposable SDK fixture") }
        let plaintext = image ? "QR file import QA-20261030" : "Text file import QA-20261030"
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["New message"].tap(); app.buttons["Myself"].tap()
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText(plaintext)
        app.swipeUp(); app.buttons["Encrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Sealed and ready."].waitForExistence(timeout:15))
        app.swipeUp(); app.buttons[image ? "Share QR image" : "Share text"].tap()
        let saveToFiles = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Save to Files")).firstMatch
        guard saveToFiles.waitForExistence(timeout:8) else { XCTFail("Save to Files is unavailable: " + app.debugDescription); return }; saveToFiles.tap()
        let save = app.buttons["Save"]
        guard save.waitForExistence(timeout:8) else { XCTFail("File save dialog missing: " + app.debugDescription); return }; save.tap()
        if app.buttons["Replace"].waitForExistence(timeout:1) { app.buttons["Replace"].tap() }
        guard app.buttons["Done"].waitForExistence(timeout:8) else { XCTFail("Export did not return to Crypton: " + app.debugDescription); return }
        for _ in 0..<3 where !app.buttons["Done"].isHittable { app.swipeUp() }
        app.buttons["Done"].tap()
        app.buttons["Decrypt message"].tap(); app.buttons["Import encrypted file"].tap()
        let recent = app.collectionViews.cells.firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout:10)); recent.tap()
        XCTAssertTrue(app.staticTexts["Sender included in v2 envelope"].waitForExistence(timeout:10))
        app.swipeUp(); app.buttons["Decrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Message opened."].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["resultText"].label,plaintext)
    }
    @MainActor private func fixture(_ path:String,_ body:[String:Any] = [:]) async throws -> [String:Any] {
        var request = URLRequest(url:URL(string:"http://127.0.0.1:18776/test/"+path)!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject:body); request.timeoutInterval = 5
        request.setValue("https://crypton.ios",forHTTPHeaderField:"Origin")
        let (bytes,response) = try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain:"fixture",code:1) }
        return try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
    }
    @MainActor func testExactCiphertextInputAndNestedLayers() async throws {
        let nested:[String:Any]
        do { nested = try await fixture("nested-for-ios") } catch { throw XCTSkip("Start the disposable SDK fixture") }
        let envelope = nested["envelope"] as! String
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["Decrypt message"].tap()
        let editor = app.textViews["messageEditor"]
        editor.tap(); editor.typeText(envelope)
        XCTAssertEqual(editor.value as? String,envelope,"Keyboard substitutions must never corrupt encrypted JSON")
        app.swipeUp(); app.buttons["Decrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Outer layer opened"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Outer note QA-20261030"].exists)
        app.buttons["Open inner layer"].tap()
        XCTAssertEqual(app.textViews["messageEditor"].value as? String,nested["inner"] as? String)
        app.swipeUp(); app.buttons["Decrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Message opened."].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["resultText"].label,"Nested inner plaintext QA-20261030")
    }
    @MainActor func testForceQuitDuringFixturePaymentBlocksSecondPayment() async throws {
        let initial:[String:Any]
        do { initial = try await fixture("delivery-stats") } catch { throw XCTSkip("Start the disposable MessageBox fixture") }
        let before = initial["payments"] as! Int
        let app = XCUIApplication()
        let arguments = ["--uitesting","--sdk-wallet-fixture","--messagebox-fixture"]
        app.launchArguments = arguments + ["--reset-qa-outbox"]; app.launch()
        app.buttons["New message"].tap(); app.buttons["Myself"].tap()
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText("Disposable force-quit test")
        app.swipeUp(); app.buttons["Encrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Sealed and ready."].waitForExistence(timeout:15))
        app.swipeUp(); app.buttons["Send with MessageBox"].tap()
        app.buttons["Check delivery fee"].tap()
        XCTAssertTrue(app.buttons["Refresh delivery fee"].waitForExistence(timeout:15))
        _ = try await fixture("hold-next-payment")
        app.buttons["Review payment in wallet and send"].tap()
        var requested = false
        for _ in 0..<40 {
            if (try await fixture("delivery-stats")["payments"] as! Int) == before+1 { requested = true; break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertTrue(requested,"The disposable wallet must have performed exactly one action before termination")
        app.terminate(); app.launchArguments = arguments; app.launch()
        app.buttons["MessageBox outbox"].tap()
        let pending = app.buttons.containing(NSPredicate(format:"label CONTAINS %@","PAYMENT_REQUESTED")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout:5)); pending.tap()
        XCTAssertFalse(app.buttons["Review payment in wallet and send"].exists)
        XCTAssertTrue(app.buttons["Check wallet history"].exists)
        app.buttons["Check wallet history"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","unsigned")).firstMatch.waitForExistence(timeout:15))
        let final = try await fixture("delivery-stats")
        XCTAssertEqual(final["payments"] as? Int,before+1,"Relaunch and recovery must not create another payment")
    }
    @MainActor private func shareRoundTrip(image:Bool) async throws {
        var request = URLRequest(url:URL(string:"http://127.0.0.1:18776/test/recipient")!)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8); request.timeoutInterval = 2
        request.setValue("https://crypton.ios",forHTTPHeaderField:"Origin")
        do { let (_,r) = try await URLSession.shared.data(for:request); if (r as? HTTPURLResponse)?.statusCode != 200 { throw NSError(domain:"fixture",code:1) } }
        catch { throw XCTSkip("Start the SDK fixture for share-extension interoperability tests.") }
        let app = XCUIApplication(); app.launchArguments = ["--uitesting","--sdk-wallet-fixture"]; app.launch()
        app.buttons["New message"].tap(); app.buttons["Myself"].tap()
        app.textViews["messageEditor"].tap(); app.textViews["messageEditor"].typeText("Shared through the native iOS extension")
        app.swipeUp(); app.buttons["Encrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Sealed and ready."].waitForExistence(timeout:15))
        app.swipeUp(); app.buttons[image ? "Share QR image" : "Share text"].tap()
        let target = app.cells["Crypton"].firstMatch
        guard target.waitForExistence(timeout:8) else { XCTFail("Crypton share extension is missing"); return }
        target.tap()
        let saved = app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH %@","Saved.")).firstMatch
        guard saved.waitForExistence(timeout:10) else { XCTFail("Share extension did not save the payload"); return }
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = image ? "Crypton QR share extension saved" : "Crypton text share extension saved"; screenshot.lifetime = .keepAlways; add(screenshot)
        let done = app.buttons["cryptonShareDone"]
        guard done.waitForExistence(timeout:5) else { XCTFail("Share extension has no Done button"); return }
        done.tap(); app.activate()
        if !app.staticTexts["Open a secret."].waitForExistence(timeout:3) {
            if app.alerts.firstMatch.exists { XCTFail("Import error: " + app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" ")); return }
            app.buttons["Settings"].tap(); app.swipeUp()
            app.buttons["Import next shared message"].tap()
        }
        XCTAssertTrue(app.staticTexts["Open a secret."].waitForExistence(timeout:5))
        app.swipeUp(); app.buttons["Decrypt message"].tap()
        XCTAssertTrue(app.staticTexts["Message opened."].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["resultText"].label,"Shared through the native iOS extension")
    }

}
