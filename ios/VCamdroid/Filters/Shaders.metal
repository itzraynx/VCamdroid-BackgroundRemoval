#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexPassThrough(uint vid [[vertex_id]],
                                    constant float4* verts [[buffer(0)]]) {
    VertexOut out;
    out.position = float4(verts[vid].xy, 0.0, 1.0);
    out.texCoord = verts[vid].zw;
    return out;
}

fragment float4 fragmentPreview(VertexOut in [[stage_in]],
                                 texture2d<float> cameraTex [[texture(0)]]) {
    constexpr sampler s(coord::normalized, filter::linear);
    return cameraTex.sample(s, in.texCoord);
}

fragment float4 fragmentMaskComposite(VertexOut in [[stage_in]],
                                       texture2d<float> cameraTex [[texture(0)]],
                                       texture2d<float> maskTex [[texture(1)]],
                                       constant float& threshold [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, filter::linear);
    float4 color = cameraTex.sample(s, in.texCoord);
    float mask = maskTex.sample(s, in.texCoord).r;
    return mask > threshold ? color : float4(0.0, 0.0, 0.0, 1.0);
}
