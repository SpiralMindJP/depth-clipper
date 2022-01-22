//
//  Renderer.swift
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

import Metal
import MetalKit
import ARKit

final class RendererParams {
    static let defaultConfidenceThreshold = ConfidenceThreshold.medium
    static let defaultNearDepthThreshold: Float = 0
    static let defaultFarDepthThreshold: Float = 0.5

    static let minDepthThreshold: Float = 0.0
    static let maxDepthThreshold: Float = 1.0
}

public enum CaptureMode: Int, CaseIterable, Identifiable {
    case trueDepth
    case lidar

    public var id: Int { self.rawValue }
}

enum ConfidenceThreshold: Int, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { self.rawValue }
}

// カメラ映像のレンダリングを行います。
final class Renderer {
    // このアプリでは横向きのみ使用
    private let orientation = UIInterfaceOrientation.portrait
    // 実行中の command buffer の最大数
    private let maxInFlightBuffers = 3

    private let mode: CaptureMode
    private let session: ARSession

    // Metal オブジェクトとテクスチャー
    private let device: MTLDevice
    private let library: MTLLibrary
    private let renderDestination: RenderDestinationProvider
    private let relaxedStencilState: MTLDepthStencilState
    private let commandQueue: MTLCommandQueue
    private lazy var renderPipelineState = makeRenderPipelineState()!

    // キャプチャーイメージ用のテクスチャーキャッシュ
    private lazy var textureCache = makeTextureCache()
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?

    // レンダーパイプラインのマルチバッファー
    private let inFlightSemaphore: DispatchSemaphore
    private var currentBufferIndex = 0

    // 現在のビューポートのサイズ
    private var viewportSize = CGSize()

    private lazy var compositeUniforms: CompositeUniforms = {
        var uniforms = CompositeUniforms()
        uniforms.viewToCamera.copy(from: viewToCamera)
        uniforms.confidenceThreshold = Int32(confidenceThreshold.rawValue)
        uniforms.nearDepthThreshold = nearDepthThreshold
        uniforms.farDepthThreshold = farDepthThreshold
        return uniforms
    }()
    private var compositeUniformsBuffers = [MetalBuffer<CompositeUniforms>]()

    // カメラデータ
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var viewToCamera = sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()

    var confidenceThreshold: ConfidenceThreshold {
        didSet {
            if confidenceThreshold == oldValue {
                return
            }
            // シェーダーに変更を適用
            compositeUniforms.confidenceThreshold = Int32(confidenceThreshold.rawValue)
        }
    }

    var nearDepthThreshold: Float {
        didSet {
            if nearDepthThreshold == oldValue {
                return
            }

            // シェーダーに変更を適用
            compositeUniforms.nearDepthThreshold = nearDepthThreshold
        }
    }

    var farDepthThreshold: Float{
        didSet {
            if farDepthThreshold == oldValue {
                return
            }

            // シェーダーに変更を適用
            compositeUniforms.farDepthThreshold = farDepthThreshold
        }
    }

    init(mode: CaptureMode, confidenceThreshold: ConfidenceThreshold, nearDepthThreshold: Float, farDepthThreshold: Float, session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.mode = mode
        self.confidenceThreshold = confidenceThreshold
        self.nearDepthThreshold = nearDepthThreshold
        self.farDepthThreshold = farDepthThreshold
        self.session = session
        self.device = device
        self.renderDestination = renderDestination

        library = try! device.makeDefaultLibrary(bundle: Bundle(for: Self.self))
        commandQueue = device.makeCommandQueue()!

        // バッファーを初期化
        for _ in 0 ..< maxInFlightBuffers {
            compositeUniformsBuffers.append(.init(device: device, count: 1, index: kCompositeUniforms.rawValue))
        }

        // 深度の読み書きには RGB は不要
        let relaxedStateDescriptor = MTLDepthStencilDescriptor()
        relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedStateDescriptor)!

        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
    }

    func drawRectResized(size: CGSize) {
        viewportSize = size
    }

    private func updateCapturedImageTextures(frame: ARFrame) {
        // 渡された frame の captured image から2つのテクスチャー (Y and CbCr) を生成
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }

        capturedImageTextureY = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)
    }

    private func updateDepthTextures(frame: ARFrame) -> Bool {
        switch self.mode {
        case .lidar:
            guard let depthMap = frame.sceneDepth?.depthMap,
                  let confidenceMap = frame.sceneDepth?.confidenceMap else {
                return false
            }

            depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
            confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        case .trueDepth:
            guard let depthMap = frame.capturedDepthData?.depthDataMap else {
                return false
            }

            depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        }

        return true
    }

    func draw() {
        guard let currentFrame = session.currentFrame else {
                return
        }
        if self.mode == .trueDepth {
            if currentFrame.capturedDepthData?.cameraCalibrationData == nil {
                return
            }
        }

        guard let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
                return
        }

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let self = self {
                self.inFlightSemaphore.signal()
            }
        }

        // フレームデータを更新
        updateCapturedImageTextures(frame: currentFrame)
        _ = updateDepthTextures(frame: currentFrame)

        // バッファーのローテーションを処理
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers

        // カメラ画像をレンダリング
        var retainingTextures = [capturedImageTextureY, capturedImageTextureCbCr]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        compositeUniformsBuffers[currentBufferIndex][0] = compositeUniforms

        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(compositeUniformsBuffers[currentBufferIndex])
        renderEncoder.setFragmentBuffer(compositeUniformsBuffers[currentBufferIndex])
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()

        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
}

// MARK: - Metal Helpers

private extension Renderer {
    func makeRenderPipelineState() -> MTLRenderPipelineState? {
        let vertexName: String
        let fragmentName: String
        switch self.mode {
        case .lidar:
            vertexName = "cameraVertex"
            fragmentName = "lidarCameraFragment"
        case .trueDepth:
            vertexName = "cameraVertex"
            fragmentName = "trueDepthCameraFragment"
        }
        guard let vertexFunction = library.makeFunction(name: vertexName) else {
                return nil
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
                return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func makeTextureCache() -> CVMetalTextureCache {
        // キャプチャー画像のテクスチャーキャッシュを生成
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)

        return cache
    }

    func makeTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)

        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)

        if status != kCVReturnSuccess {
            texture = nil
        }

        return texture
    }
}
