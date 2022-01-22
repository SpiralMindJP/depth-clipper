//
//  Helpers.swift
//  DentDetector
//
//  Created by Ryosuke Akiyama 2022/01/21.
//

import simd
import CoreGraphics
import AVFoundation

typealias Float3 = SIMD3<Float>

extension matrix_float3x3 {
    mutating func copy(from affine: CGAffineTransform) {
        columns.0 = Float3(Float(affine.a), Float(affine.c), Float(affine.tx))
        columns.1 = Float3(Float(affine.b), Float(affine.d), Float(affine.ty))
        columns.2 = Float3(0, 0, 1)
    }
}
