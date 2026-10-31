import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let privacyTag = 871041
    func sceneWillResignActive(_ scene:UIScene) {
        guard let window = window, window.viewWithTag(privacyTag) == nil else { return }
        let cover = UIView(frame:window.bounds); cover.tag = privacyTag; cover.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        cover.backgroundColor = UIColor(red:0.025,green:0.045,blue:0.075,alpha:1); window.addSubview(cover)
    }
    func sceneDidBecomeActive(_ scene:UIScene) { window?.viewWithTag(privacyTag)?.removeFromSuperview() }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene:scene)
        window.rootViewController = UIHostingController(rootView:CryptonView())
        self.window = window; window.makeKeyAndVisible()
        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.async { NotificationCenter.default.post(name:.cryptonImport,object:url) }
        }
    }
    func scene(_ scene:UIScene,openURLContexts URLContexts:Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { NotificationCenter.default.post(name:.cryptonImport,object:url) }
    }
}
extension Notification.Name { static let cryptonImport = Notification.Name("cryptonImport") }
