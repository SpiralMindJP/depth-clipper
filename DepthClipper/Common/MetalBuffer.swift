//
//  MetalBuffer.swift
//  DentDetector
//
//  Created by Ryosuke Akiyama 2022/01/21.
//

import AVFoundation
import Foundation

protocol Resource {
    associatedtype Element
}

/// MTLBuffer 内部への型安全なアクセスおよび代入を提供するラッパー
struct MetalBuffer<Element>: Resource {

    /// 基になる MTLBuffer
    fileprivate let buffer: MTLBuffer

    /// エンコード中にバッファーがバインドされるべきインデックス。
    /// Metal シェーダー内で期待されるバッファーのインデックスに一致する必要あり。
    fileprivate let index: Int

    /// バッファーが保持する要素数
    let count: Int
    var stride: Int {
        MemoryLayout<Element>.stride
    }

    /// バッファーをゼロで初期化し、指定された要素数を基に適切な長さを割り当てます。
    init(device: MTLDevice, count: Int, index: UInt32, label: String? = nil, options: MTLResourceOptions = []) {

        guard let buffer = device.makeBuffer(length: MemoryLayout<Element>.stride * count, options: options) else {
            fatalError("Failed to create MTLBuffer.")
        }
        self.buffer = buffer
        self.buffer.label = label
        self.count = count
        self.index = Int(index)
    }

    /// 指定された配列の内容でバッファーを初期化します。
    init(device: MTLDevice, array: [Element], index: UInt32, options: MTLResourceOptions = []) {

        guard let buffer = device.makeBuffer(bytes: array, length: MemoryLayout<Element>.stride * array.count, options: .storageModeShared) else {
            fatalError("Failed to create MTLBuffer")
        }
        self.buffer = buffer
        self.count = array.count
        self.index = Int(index)
    }

    /// バッファーの指定された要素のインデックスのメモリーを提供された値で置き換えます。
    func assign<T>(_ value: T, at index: Int = 0) {
        precondition(index <= count - 1, "Index \(index) is greater than maximum allowable index of \(count - 1) for this buffer.")
        withUnsafePointer(to: value) {
            buffer.contents().advanced(by: index * stride).copyMemory(from: $0, byteCount: stride)
        }
    }

    /// バッファーのメモリーを配列の値で置き換えます。
    func assign<Element>(with array: [Element]) {
        let byteCount = array.count * stride
        precondition(byteCount == buffer.length, "Mismatch between the byte count of the array's contents and the MTLBuffer length.")
        buffer.contents().copyMemory(from: array, byteCount: byteCount)
    }

    func contents(from offset: Int = 0, count: Int?) -> [Element] {
        let count = count ?? self.count
        precondition(offset + count <= self.count, "Offset \(offset) count \(count - 1) is incorrect.")

        let elements = UnsafeRawBufferPointer(start: self.buffer.contents().advanced(by: offset * stride), count: count * stride).bindMemory(to: Element.self)
        return .init(elements)
    }

    /// バッファー内の指定された要素のインデックスの値のコピーを返します。
    subscript(index: Int) -> Element {
        get {
            precondition(stride * index <= buffer.length - stride, "This buffer is not large enough to have an element at the index: \(index)")
            return buffer.contents().advanced(by: index * stride).load(as: Element.self)
        }

        set {
            assign(newValue, at: index)
        }
    }

}

// Note: MetalBuffer<T>.buffer は fileprivate なので、この拡張を当ファイルに配置します。
// MetalBuffer<T>.buffer へのアクセスは、このファイルだけが基になる MTLBuffer に触れるように fileprivate にしています。
extension MTLRenderCommandEncoder {
    func setVertexBuffer<T>(_ vertexBuffer: MetalBuffer<T>, offset: Int = 0) {
        setVertexBuffer(vertexBuffer.buffer, offset: offset, index: vertexBuffer.index)
    }

    func setFragmentBuffer<T>(_ fragmentBuffer: MetalBuffer<T>, offset: Int = 0) {
        setFragmentBuffer(fragmentBuffer.buffer, offset: offset, index: fragmentBuffer.index)
    }

    func setVertexResource<R: Resource>(_ resource: R) {
        if let buffer = resource as? MetalBuffer<R.Element> {
            setVertexBuffer(buffer)
        }

        if let texture = resource as? Texture {
            setVertexTexture(texture.texture, index: texture.index)
        }
    }

    func setFragmentResource<R: Resource>(_ resource: R) {
        if let buffer = resource as? MetalBuffer<R.Element> {
            setFragmentBuffer(buffer)
        }

        if let texture = resource as? Texture {
            setFragmentTexture(texture.texture, index: texture.index)
        }
    }
}

struct Texture: Resource {
    typealias Element = Any

    let texture: MTLTexture
    let index: Int
}
