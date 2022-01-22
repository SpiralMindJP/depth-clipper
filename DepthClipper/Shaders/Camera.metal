//
//  Camera.metal
//  DepthClipper
//
//  Created by Ryosuke Akiyama on 2022/01/21.
//

#include <metal_stdlib>
using namespace metal;

#include <simd/simd.h>
#import "ShaderTypes.h"

constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
constant auto yCbCrToRGB = float4x4(float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));
constant float2 viewVertices[] = { float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1) };
constant float2 viewTexCoords[] = { float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1) };

struct VertexOut
{
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut cameraVertex(uint vertexID [[vertex_id]],
                                 constant CompositeUniforms& uniforms [[buffer(kCompositeUniforms)]]) {
    const float3 texCoord = float3(viewTexCoords[vertexID], 1) * uniforms.viewToCamera;

    VertexOut out;
    out.position = float4(viewVertices[vertexID], 0, 1);
    out.texCoord = texCoord.xy;

    return out;
}

fragment float4 trueDepthCameraFragment(VertexOut in [[stage_in]],
                                  constant CompositeUniforms& uniforms [[buffer(kCompositeUniforms)]],
                                  texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                                  texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]],
                                  texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]]) {
    const auto textureCoordinate = in.texCoord;

    // 深度マップをサンプリングし、深度の値を取得
    const auto depth = depthTexture.sample(colorSampler, textureCoordinate).r;

    // Y および CbCr のテクスチャーをサンプリングし、与えられたテクスチャ座標の YCbCr カラーを取得
    const auto ycbcr = float4(capturedImageTextureY.sample(colorSampler, textureCoordinate).r, capturedImageTextureCbCr.sample(colorSampler, textureCoordinate).rg, 1);
    const auto sampledColor = (yCbCrToRGB * ycbcr).rgb;

    // 深度が閾値の範囲内の場合のみカラーを描画
    const auto near = uniforms.nearDepthThreshold;
    const auto far = uniforms.farDepthThreshold;
    if (isnan(depth) || depth < near || depth > far) {
        return float4(0.0f, 1.0f, 0.0f, 1.0f);
    } else {
        return float4(sampledColor, 1.0f);
    }
}

fragment float4 lidarCameraFragment(VertexOut in [[stage_in]],
                                  constant CompositeUniforms& uniforms [[buffer(kCompositeUniforms)]],
                                  texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                                  texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]],
                                  texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]]) {
    const auto textureCoordinate = in.texCoord;

    // 深度マップをサンプリングし、深度の値を取得
    const auto depth = depthTexture.sample(colorSampler, textureCoordinate).r;

    // Y および CbCr のテクスチャーをサンプリングし、与えられたテクスチャ座標の YCbCr カラーを取得
    const auto ycbcr = float4(capturedImageTextureY.sample(colorSampler, textureCoordinate).r, capturedImageTextureCbCr.sample(colorSampler, textureCoordinate).rg, 1);
    const auto sampledColor = (yCbCrToRGB * ycbcr).rgb;

    // 深度が閾値の範囲内の場合のみカラーを描画
    const auto near = uniforms.nearDepthThreshold;
    const auto far = uniforms.farDepthThreshold;
    if (isnan(depth) || depth < near || depth > far) {
        return float4(0.0f, 1.0f, 0.0f, 1.0f);
    } else {
        return float4(sampledColor, 1.0f);
    }
}
