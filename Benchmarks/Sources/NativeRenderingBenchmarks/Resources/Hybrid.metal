#include <metal_stdlib>
using namespace metal;

struct Quad { float4 position [[position]]; float2 uv; };
vertex Quad fullscreen(uint id [[vertex_id]]) {
    const float2 points[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    Quad out; out.position=float4(points[id],0,1);
    out.uv=float2(points[id].x*0.5+0.5,0.5-points[id].y*0.5); return out;
}

kernel void field(texture2d<half,access::write> output [[texture(0)]],
    constant float4 &time [[buffer(0)]],uint2 p [[thread_position_in_grid]]) {
    if (p.x>=output.get_width()||p.y>=output.get_height()) return;
    float2 uv=(float2(p)+0.5)/float2(output.get_width(),output.get_height());
    float wave=0.5+0.5*sin(uv.x*18+time.x)*cos(uv.y*12-time.x*0.7);
    output.write(half4(0.08+wave*4,0.12+wave*0.7,0.3+wave*2,1),p);
}

fragment half4 shade(Quad in [[stage_in]],texture2d<half> image [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::linear);
    return image.sample(s,in.uv);
}

struct BackdropCoordinates {
    float4 sourceBounds,outputBounds,localToContextX,localToContextY;
    float4 contextToLocalX,contextToLocalY,properties;
};
fragment float4 glass(Quad in [[stage_in]],texture2d<float> backdrop [[texture(0)]],
    constant float4 &time [[buffer(0)]],constant BackdropCoordinates &mapping [[buffer(1)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::linear);
    float2 host=mapping.sourceBounds.xy+in.uv*mapping.sourceBounds.zw;
    float2 local=float2(dot(mapping.contextToLocalX.xyz,float3(host,1)),dot(mapping.contextToLocalY.xyz,float3(host,1)));
    float2 offset=3*float2(sin(local.y*0.12+time.x),cos(local.x*0.1-time.x));
    float2 displacement=float2(dot(mapping.localToContextX.xy,offset),dot(mapping.localToContextY.xy,offset));
    float4 color=backdrop.sample(s,in.uv+displacement/mapping.sourceBounds.zw);
    return color*float4(0.88,0.96,1,1);
}
