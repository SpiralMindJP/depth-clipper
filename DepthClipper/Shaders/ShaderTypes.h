//
//  ShaderTypes.h
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

enum TextureIndices {
    kTextureY = 0,
    kTextureCbCr = 1,
    kTextureDepth = 2,
    kTextureConfidence = 3
};

enum BufferIndices {
    kCompositeUniforms = 0,
};

struct CompositeUniforms {
    matrix_float3x3 viewToCamera;
    float nearDepthThreshold;
    float farDepthThreshold;
    int confidenceThreshold;
};

#endif /* ShaderTypes_h */
