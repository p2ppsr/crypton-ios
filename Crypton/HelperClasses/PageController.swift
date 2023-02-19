//
//  PageController.swift
//  Crypton
//
//  Created by Brayden Langley on 2/13/23.
//

import Foundation

import UIKit
class PageController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    
    var pages = [UIViewController]()
    var currentIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.dataSource = self

        let page1: UIViewController! = storyboard?.instantiateViewController(withIdentifier: "page1")
        let page2: UIViewController! = storyboard?.instantiateViewController(withIdentifier: "page2")
        let page3: UIViewController! = storyboard?.instantiateViewController(withIdentifier: "page3")
        let page4: UIViewController! = storyboard?.instantiateViewController(withIdentifier: "page4")

        pages.append(page1)
        pages.append(page2)
        pages.append(page3)
        pages.append(page4)

        setViewControllers([page1], direction: UIPageViewController.NavigationDirection.forward, animated: false, completion: nil)
        
        let pageControl = UIPageControl.appearance(whenContainedInInstancesOf: [UIPageViewController.self])
        pageControl.pageIndicatorTintColor = UIColor.gray
        pageControl.currentPageIndicatorTintColor = UIColor(red: 131/255, green: 228/255, blue: 150/255, alpha: 1)
        pageControl.backgroundColor = UIColor.clear

        let pageControlSize = pageControl.size(forNumberOfPages: 2)
        let pageControlX = view.center.x - pageControlSize.width/2
        let pageControlY = view.bounds.maxY - pageControlSize.height - 30
        let pageControlFrame = CGRect(x: pageControlX, y: pageControlY, width: pageControlSize.width, height: pageControlSize.height)
        let pageControlView = UIPageControl(frame: pageControlFrame)
        pageControlView.numberOfPages = pages.count
        pageControlView.currentPage = 0
        view.addSubview(pageControlView)

    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController) else {
            return nil
        }
        let previousIndex = index - 1
        guard previousIndex >= 0 else {
            return nil
        }
        currentIndex = previousIndex
        return pages[previousIndex]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = pages.firstIndex(of: viewController) else {
            return nil
        }
        let nextIndex = index + 1
        guard nextIndex < pages.count else {
            return nil
        }
        currentIndex = nextIndex
        return pages[nextIndex]
    }

    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return pages.count
    }

    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        return currentIndex
    }
}
