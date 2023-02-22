//
//  GuidePage.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation
import UIKit

class GuidePage: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    @IBAction func restartGuide(_ sender: Any) {
        if let parent = self.parent as? PageController {
            parent.restartGuide()
        }
    }
    @IBAction func endGuide(_ sender: Any) {
        // Get the current window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        // Get the current window
        guard let window = windowScene.windows.first else {
            return
        }

        // Load the storyboard that contains the root view controller and the navigation controller
        let storyboard = UIStoryboard(name: "Main", bundle: nil)

        // Instantiate the root view controller with the specified identifier
        let rootViewController = storyboard.instantiateViewController(withIdentifier: "MainVC")

        // Instantiate the navigation controller and set its root view controller
        let navController = UINavigationController(rootViewController: rootViewController)

        // Set the new navigation controller as the root view controller of the window with a transition animation
        UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {
            window.rootViewController = navController
        }, completion: nil)
    }
}
