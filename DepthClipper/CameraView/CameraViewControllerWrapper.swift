//
//  CameraViewControllerWrapper.swift
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

import Foundation

import SwiftUI

struct CameraViewControllerWrapper: UIViewControllerRepresentable {
    let mode: CaptureMode
    let confidenceThreshold: ConfidenceThreshold
    let nearDepthThreshold: Float
    let farDepthThreshold: Float

    func makeCoordinator() -> CameraViewControllerWrapper.Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<CameraViewControllerWrapper>) -> CameraViewController {
        let viewController = CameraViewController(mode: self.mode, confidenceThreshold: self.confidenceThreshold, nearDepthThreshold: self.nearDepthThreshold, farDepthThreshold: self.farDepthThreshold)
        viewController.delegate = context.coordinator

        return viewController
    }

    func updateUIViewController(_ viewController: CameraViewController, context: UIViewControllerRepresentableContext<CameraViewControllerWrapper>) {
        viewController.setConfidenceThreshold(threshold: self.confidenceThreshold)
        viewController.setNearDepthThreshold(threshold: self.nearDepthThreshold)
        viewController.setFarDepthThreshold(threshold: self.farDepthThreshold)
        print("nearDepthThreshold: \(self.nearDepthThreshold)")
        print("farDepthThreshold : \(self.farDepthThreshold)")
    }

    typealias UIViewControllerType = CameraViewController

    class Coordinator: NSObject, CameraViewControllerDelegate {
        var parent: CameraViewControllerWrapper

        init(_ cameraView: CameraViewControllerWrapper) {
            self.parent = cameraView
        }
    }
}
