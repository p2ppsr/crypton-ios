import Foundation
import WebKit
import Combine

@available(iOS 13.0, *)
class BabbageSDK: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    
//    public let webView: WKWebView
    @IBOutlet var webView: WKWebView!
    
    public typealias Callback = (String) -> Void
    public var callbackIDMap: [String : Callback]
    
    // TODO: Move to client app?
    let PROTOCOL_ID = "crypton"
    let KEY_ID = "1"
    let HADES_BASE_URL = "http://localhost:3000" // https://staging-mobile-portal.babbage.systems
    
    public required init?(coder: NSCoder) {
//        self.webView = webView
        self.callbackIDMap = [:]
        super.init(coder: coder)
    }
    
    // Defines the structure of a BabbageResponse
    public struct BabbageResponse: Decodable {
        enum Category: String, Decodable {
            case swift, combine, debugging, xcode
        }

        public let type: String
        public let result: String
        public let id: String
        
        // Initialize the properties
        public init(type: String, result: String, id: String){
            self.type = type
            self.result = result
            self.id = id
        }
    }
    public struct BabbageResponseWithArray: Decodable {
        public let type: String
        public let result: [String]
        public let id: String
        
        // Initialize the properties
        public init(type: String, result: [String], id: String){
            self.type = type
            self.result = result
            self.id = id
        }
    }

    // Defines the structure of a BabbageCommand
    public struct BabbageCommand: Encodable {
        public let type: String
        public let call: String
        public let params: [String:String]
        public var id: String
        
        // Initialize the properties
        public init(type: String, call: String, params: [String:String], id: String){
            self.type = type
            self.call = call
            self.params = params
            self.id = id
        }
    }
    
    public override func loadView() {
        super.loadView()
        // Do any additional setup after loading the view.
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "babbage-webview-inlay"

        // Disable zooming on webview
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" +
            "head.appendChild(meta);"
        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        // Load the request url for hades server
        let request = NSURLRequest(url: URL(string: HADES_BASE_URL)!)
        webView.load(request as URLRequest)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "Confirm", style: .destructive, handler: { (action) in
            completionHandler(true)
        }))

        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(false)
        }))

        present(alertController, animated: true, completion: nil)
    }

    // Callback recieved from webkit.messageHandler.postMessage
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //This function handles the events coming from javascript.
        guard let response = message.body as? String else { return }
        
        if (message.name == "closeBabbage") {
              webView.isHidden = true
        } else if (message.name == "openBabbage") {
              webView.isHidden = false
        } else {
            callbackIDMap[message.name]!(response)
        }
    }
    
    // Webview call back for when the view loads
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // This function is called when the webview finishes navigating to the webpage.
      // We use this to send data to the webview when it's loaded.
        print("loaded")
        let id:String = (generateCallbackID())
        webView.configuration.userContentController.add(self, name: id)
        
        Task.init {
            if #available(iOS 15.0, *) {
                let isAuthenticated:Bool? = await isAuthenticated(id: id)
                
                // Show/Hide the webview
                if (isAuthenticated!) {
                    webView.isHidden = true
                    performSegue(withIdentifier: "showApp", sender: self)
                } else {
                    webView.isHidden = false
                    let id:String = (generateCallbackID())
                    webView.configuration.userContentController.add(self, name: id)
                    await waitForAuthentication(id: id)
                    webView.isHidden = true
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }

    // Encrypts data using CWI.encrypt
    @available(iOS 15.0, *)
    public func encrypt(plaintext: String, protocolID: String, keyID: String, id: String) async -> String {
        let cmd = BabbageCommand(type: "CWI", call: "encrypt", params: ["plaintext": plaintext, "protocolID": protocolID, "keyID": keyID, "originator": "projectbabbage.com", "returnType": "string"], id: id)
        
        struct EncryptedText: Decodable {
            let result: String
        }
        
        let result: String = await runCommand(webView: webView, cmd: cmd).value
        let encryptedText = try! JSONDecoder().decode(EncryptedText.self, from:result.data(using: .utf8)!)
        
        return encryptedText.result
    }

    // Encrypts data using CWI.decrypt
    @available(iOS 15.0, *)
    public func decrypt(ciphertext: String, protocolID: String, keyID: String, id: String) async -> String {
        let cmd = BabbageCommand(type: "CWI", call: "decrypt", params: ["ciphertext": ciphertext, "protocolID": protocolID, "keyID": keyID, "originator": "projectbabbage.com", "returnType": "string"], id: id)
        
        struct DecryptedText: Decodable {
            let result: String
        }
        
        let result: String = await runCommand(webView: webView, cmd: cmd).value
        let decryptedText = try! JSONDecoder().decode(DecryptedText.self, from:result.data(using: .utf8)!)
        return decryptedText.result
    }
    
    @available(iOS 15.0, *)
    public func isAuthenticated(id: String) async -> Bool {
        struct ResponseObject: Decodable {
            let result:Bool
        }
        
        let cmd = BabbageCommand(type: "CWI", call:"isAuthenticated", params: [:], id: id)
        let result = await runCommand(webView: webView, cmd: cmd).value
        let responseObject:ResponseObject = try! JSONDecoder().decode(ResponseObject.self, from:result.data(using: .utf8)!)
        let authenticationStatus:Bool = responseObject.result
        return authenticationStatus
    }
    
    @available(iOS 15.0, *)
    public func waitForAuthentication(id: String) async -> Bool {
        struct ResponseObject: Decodable {
            let result:Bool
        }
        
        let cmd = BabbageCommand(type: "CWI", call:"waitForAuthentication", params: [:], id: id)
        let result = await runCommand(webView: webView, cmd: cmd).value
        let responseObject:ResponseObject = try! JSONDecoder().decode(ResponseObject.self, from:result.data(using: .utf8)!)
        let authenticationStatus:Bool = responseObject.result
        return authenticationStatus
    }
    
    public func generateCallbackID() -> String {
        return NSUUID().uuidString
    }

    // Execute the BabbageCommand
    public func runCommand(webView: WKWebView, cmd: BabbageCommand)-> Combine.Future <String, Never> {
        let result = Future<String, Never>() { promise in
            let callback: Callback = { response in
            
                print(response)
                self.callbackIDMap.removeValue(forKey: cmd.id)
                promise(Result.success(response))
            }

            self.callbackIDMap[cmd.id] = callback
            print(self.callbackIDMap)
        }
        do {
            let jsonData = try JSONEncoder().encode(cmd)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            DispatchQueue.main.async {
                webView.evaluateJavaScript("window.postMessage(\(jsonString))")
            }
        } catch {
            // TODO
        }
        return result
    }
}
