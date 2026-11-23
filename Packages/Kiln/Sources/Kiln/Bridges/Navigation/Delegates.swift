//
//  Delegates.swift
//  Bridges: UIKit's navigation delegate (PLAN.md §1.5)
//
//  `UINavigationControllerDelegate` is what a `UIImagePickerController`'s
//  delegate adopts alongside `UIImagePickerControllerDelegate` (Camera.swift).
//  Its methods are all optional; the proxy forwards the ones the app writes.
//

import SwiftUI

extension NavigationBridges {
    static func delegates(_ r: KRegistry) {
        r.delegateProtocol("UINavigationControllerDelegate", .navigation,
                           requirements: ["navigationController(_:willShow:animated:)?", "navigationController(_:didShow:animated:)?"],
                           notes: "With `UIImagePickerControllerDelegate`.")
    }
}
