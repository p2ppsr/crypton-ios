//
//  LoadingAnimation.swift
//  Crypton
//
//  Created by Brayden Langley on 2/19/23.
//

import Foundation
import UIKit
import FLAnimatedImage

func addLoadingAnimation(parentView: UIView) -> FLAnimatedImageView {
    let loadingGif = FLAnimatedImageView()
    guard let gifData = NSDataAsset(name: "loader")?.data else { return loadingGif }
    let gif = FLAnimatedImage(animatedGIFData: gifData)
  
    // Set the loop completion block to reset the frame index and restart the animation
    loadingGif.loopCompletionBlock = { (uint: UInt) -> Void in
    // unit is the loop time of image.
        loadingGif.stopAnimating()
    }
    
    loadingGif.animatedImage = gif
    loadingGif.center = parentView.center
    loadingGif.frame = CGRect(x: 0, y: 0, width: parentView.frame.width, height: parentView.frame.height)
    loadingGif.center = parentView.center
    
    loadingGif.stopAnimating()
    loadingGif.isHidden = true
    parentView.addSubview(loadingGif)
    return loadingGif
}
