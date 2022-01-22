//
//  CameraViewController.swift
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

import UIKit
import Metal
import MetalKit
import ARKit

protocol CameraViewControllerDelegate {
}

final class CameraViewController: UIViewController, ARSessionDelegate {
    private let mode: CaptureMode
    private let initConfidenceThreshold: ConfidenceThreshold
    private let initNearDepthThreshold: Float
    private let initFarDepthThreshold: Float

    private var device: MTLDevice!
    private let session = ARSession()
    private var renderer: Renderer!

    var delegate: CameraViewControllerDelegate?

    init(mode: CaptureMode, confidenceThreshold: ConfidenceThreshold, nearDepthThreshold: Float, farDepthThreshold: Float) {
        self.mode = mode
        self.initConfidenceThreshold = confidenceThreshold
        self.initNearDepthThreshold = nearDepthThreshold
        self.initFarDepthThreshold = farDepthThreshold

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.mode = .lidar
        self.initConfidenceThreshold = RendererParams.defaultConfidenceThreshold
        self.initNearDepthThreshold = RendererParams.defaultNearDepthThreshold
        self.initFarDepthThreshold = RendererParams.defaultFarDepthThreshold
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        self.device = device

        self.session.delegate = self

        let view = MTKView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.device = device

        view.backgroundColor = UIColor.clear
        // depth test を有効にする必要あり
        view.depthStencilPixelFormat = .depth32Float
        view.contentScaleFactor = 1
        view.delegate = self
        self.view = view

        // Renderer が view に描画するよう構成する
        self.renderer = Renderer(mode: self.mode, confidenceThreshold: self.initConfidenceThreshold, nearDepthThreshold: self.initNearDepthThreshold, farDepthThreshold: self.initFarDepthThreshold, session: session, metalDevice: device, renderDestination: view)
        self.renderer.drawRectResized(size: view.bounds.size)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // ARSession を初期化
        self.initARSession()

        // キャプチャー中に画面が暗くならないようにする
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // ARSession を一時停止
        self.session.pause()
    }

    func setConfidenceThreshold(threshold: ConfidenceThreshold) {
        self.renderer.confidenceThreshold = threshold
    }

    func setNearDepthThreshold(threshold: Float) {
        self.renderer.nearDepthThreshold = threshold
    }

    func setFarDepthThreshold(threshold: Float) {
        self.renderer.farDepthThreshold = threshold
    }

    // ホームインジケーターを非表示にする
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    // ステータスバーを非表示にする
    override var prefersStatusBarHidden: Bool {
        return true
    }

    func initARSession() {
        var configuration: ARConfiguration
        if self.mode == .lidar {
            configuration = self.lidarARConfig()
        } else if self.mode == .trueDepth {
            configuration = self.trueDepthARConfig()
        } else {
            return
        }

        // View のセッションを実行する
        session.run(configuration, options: [.removeExistingAnchors, .resetSceneReconstruction, .resetTracking, .stopTrackedRaycasts])
    }

    func lidarARConfig() -> ARConfiguration {
        // World tracking 構成を生成し、scene depth フレームセマンティックを有効にする
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        print("world alignment: \(config.worldAlignment.rawValue)")
        print("gravity          : \(ARConfiguration.WorldAlignment.gravity.rawValue)")
        print("gravityAndHeading: \(ARConfiguration.WorldAlignment.gravityAndHeading.rawValue)")
        print("camera           : \(ARConfiguration.WorldAlignment.camera.rawValue)")
        return config
    }

    func trueDepthARConfig() -> ARConfiguration {
        let config = ARFaceTrackingConfiguration()
        config.worldAlignment = .gravity
        config.isLightEstimationEnabled = true
        config.isWorldTrackingEnabled = true
        if ARFaceTrackingConfiguration.supportsWorldTracking {
            config.isWorldTrackingEnabled = true
        }
        return config
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        // ユーザーにエラーメッセージを表示する
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // エラーが発生したことを通知するアラートを表示する
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                if let configuration = self.session.configuration {
                    self.session.run(configuration, options: .resetSceneReconstruction)
                }
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

// MARK: - MTKViewDelegate

extension CameraViewController: MTKViewDelegate {
    // ビューの向きやレイアウトが変更されたときに呼出される
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.renderer.drawRectResized(size: size)
    }

    // View をレンダリングする必要があるときに呼出される
    func draw(in view: MTKView) {
        self.renderer.draw()
    }
}

// MARK: - RenderDestinationProvider

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {

}

