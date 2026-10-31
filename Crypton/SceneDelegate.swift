import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
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
