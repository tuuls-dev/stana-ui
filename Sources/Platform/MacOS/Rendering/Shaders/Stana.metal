#include <metal_stdlib>
using namespace metal;
struct Quad {
    float4 rect, uv, color, clip;
    float4 row0, row1, target, options;
    uint mode, linear, sourceLinear, masked;
};
struct VOut { float4 position [[position]]; float2 uv; float2 local; uint index [[flat]]; };
float3 decodeSRGB(float3 v) {
    return select(pow((v+0.055f)/1.055f,float3(2.4f)),v/12.92f,v<=0.04045f);
}
float3 encodeSRGB(float3 v) {
    return select(1.055f*pow(max(v,float3(0)),float3(1.0f/2.4f))-0.055f,12.92f*v,v<=0.0031308f);
}
float4 convertColor(float4 c, bool sourceLinear, bool linear) {
    if (c.a<=0) return float4(0);
    if (sourceLinear==linear) return c;
    float3 straight=c.rgb/c.a;
    return float4((linear?decodeSRGB(straight):encodeSRGB(straight))*c.a,c.a);
}
vertex VOut stn_quad(uint id [[vertex_id]], constant Quad &q [[buffer(0)]]) {
    const float2 v[6]={float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
    float2 p=q.rect.xy+v[id]*q.rect.zw;
    float2 mapped=float2(dot(q.row0.xyz,float3(p,1)),dot(q.row1.xyz,float3(p,1)));
    float2 ndc=(mapped-q.target.xy)/q.target.zw;
    VOut out; out.position=float4(ndc.x*2-1,1-ndc.y*2,0,1); out.local=p; out.index=0;
    out.uv=q.uv.xy+v[id]*q.uv.zw; return out;
}
float coverage(float2 p, float4 rect, float radius, bool ellipse) {
    float2 halfSize=rect.zw*0.5f;
    float2 v=p-rect.xy-halfSize;
    float sd;
    if (ellipse) {
        float2 n=v/max(halfSize,float2(0.00001f));
        sd=(length(n)-1)*min(halfSize.x,halfSize.y);
    } else {
        float r=min(radius,min(halfSize.x,halfSize.y));
        float2 d=abs(v)-(halfSize-r);
        sd=length(max(d,float2(0)))+min(max(d.x,d.y),0.0f)-r;
    }
    return clamp(0.5f-sd/max(fwidth(sd),0.00001f),0.0f,1.0f);
}
fragment float4 stn_fragment(VOut in [[stage_in]], constant Quad &q [[buffer(0)]],
    texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 c;
    if (q.mode==1) {
        c=float4(q.color.rgb*q.color.a,q.color.a);
    } else {
        c=image.sample(s,in.uv);
    }
    if (q.mode==2) c.rgb*=c.a;
    c=convertColor(c,q.sourceLinear,q.linear);
    float alpha=q.options.z;
    if (q.masked) alpha*=coverage(in.local,q.clip,q.options.x,q.options.y>0);
    return c*alpha;
}
fragment float4 stn_line(VOut in [[stage_in]],constant Quad &q [[buffer(0)]],device const packed_float2 *points [[buffer(1)]]) {
    float2 p=in.local-q.rect.xy; float distance=INFINITY; uint count=uint(q.options.y);
    if (count==1) distance=length(p-float2(points[0]));
    for (uint i=1;i<count;i++) { float2 a=float2(points[i-1]),b=float2(points[i]),v=b-a;
        float t=dot(v,v)>0?clamp(dot(p-a,v)/dot(v,v),0.0f,1.0f):0; distance=min(distance,length(p-a-t*v)); }
    float coverage=clamp(0.5f-(distance-q.options.x*0.5f)/max(fwidth(distance),0.00001f),0.0f,1.0f);
    return convertColor(float4(q.color.rgb*q.color.a,q.color.a),q.sourceLinear,q.linear)*coverage;
}
struct MeshVertex { packed_float2 position; packed_float4 color; };
struct MeshOut { float4 position [[position]]; float4 color; };
vertex MeshOut stn_mesh(uint id [[vertex_id]], device const MeshVertex *vertices [[buffer(0)]],
    constant Quad &q [[buffer(1)]]) {
    MeshVertex v=vertices[id]; float2 p=float2(v.position)+q.rect.xy;
    float2 mapped=float2(dot(q.row0.xyz,float3(p,1)),dot(q.row1.xyz,float3(p,1)));
    float2 ndc=(mapped-q.target.xy)/q.target.zw;
    MeshOut out; out.position=float4(ndc.x*2-1,1-ndc.y*2,0,1);
    float4 c=float4(v.color); out.color=convertColor(float4(c.rgb*c.a,c.a),true,q.linear); return out;
}
fragment float4 stn_mesh_fragment(MeshOut in [[stage_in]]) { return in.color; }
struct Filter { uint width,height,radius,horizontal; float2 direction; };
kernel void stn_blur(texture2d<float,access::sample> input [[texture(0)]],
    texture2d<float,access::write> output [[texture(1)]],constant Filter &p [[buffer(0)]],
    uint2 id [[thread_position_in_grid]]) {
    if (id.x>=p.width||id.y>=p.height) return;
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::linear);
    float4 sum=0; int r=int(p.radius); float2 dimensions=float2(p.width,p.height);
    for (int i=-r;i<=r;i++) {
        float2 at=float2(id)+0.5f+float(i)*p.direction; sum+=input.sample(s,at/dimensions);
    }
    float4 c=sum/float(2*r+1); if (c.a<=0) c=0; output.write(c,id);
}
struct Replace { float4 context, panel, row0, row1, options, source, foreground; };
kernel void stn_replace(texture2d<float,access::read> prefix [[texture(0)]],
    texture2d<float,access::sample> effect [[texture(1)]],
    texture2d<float,access::sample> foreground [[texture(2)]],
    texture2d<float,access::write> output [[texture(3)]],constant Replace &p [[buffer(0)]],
    uint2 id [[thread_position_in_grid]]) {
    if (id.x>=output.get_width()||id.y>=output.get_height()) return;
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::linear);
    float2 host=p.context.xy+(float2(id)+0.5f)/p.options.x;
    float2 local=float2(dot(p.row0.xyz,float3(host,1)),dot(p.row1.xyz,float3(host,1)));
    float2 uv=(local-p.foreground.xy)/p.foreground.zw;
    float4 b=prefix.read(id), f=p.options.w>0?b:effect.sample(s,(host-p.source.xy)/p.source.zw);
    float4 c=foreground.sample(s,uv); float4 r=c+f*(1-c.a);
    float2 v=local-p.panel.xy-p.panel.zw*0.5f;
    float radius=min(p.options.y,min(p.panel.z,p.panel.w)*0.5f);
    float2 d=abs(v)-(p.panel.zw*0.5f-radius);
    float sd=length(max(d,float2(0)))+min(max(d.x,d.y),0.0f)-radius;
    float w=clamp(0.5f-sd*p.options.x,0.0f,1.0f)*p.options.z;
    output.write(mix(b,r,w),id);
}
vertex VOut stn_batch_quad(uint id [[vertex_id]],uint instance [[instance_id]],constant Quad *quads [[buffer(0)]]) {
    constant Quad &q=quads[instance];
    const float2 v[6]={float2(0,0),float2(1,0),float2(0,1),float2(0,1),float2(1,0),float2(1,1)};
    float2 p=q.rect.xy+v[id]*q.rect.zw; float2 ndc=(p-q.target.xy)/q.target.zw;
    VOut out; out.position=float4(ndc.x*2-1,1-ndc.y*2,0,1); out.local=p;
    out.uv=q.uv.xy+v[id]*q.uv.zw; out.index=instance; return out;
}
float4 stn_display(float4 c,constant Quad &q) {
    if (!q.linear) return c;
    if (c.a<=0) return float4(0);
    float3 straight=c.rgb/c.a;
    float L=max(0.0f,max(straight.r,max(straight.g,straight.b)));
    float H=max(1.0f,q.options.w), K=min(1.0f,0.75f*H);
    if (L>K) straight*=(K+(H-K)*(L-K)/((L-K)+(H-K)))/L;
    if (!q.sourceLinear) straight=encodeSRGB(straight);
    return float4(straight*c.a,c.a);
}
fragment float4 stn_present_batch(VOut in [[stage_in]],constant Quad *quads [[buffer(0)]],
    array<texture2d<float>,16> images [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::nearest);
    return stn_display(images[in.index].sample(s,in.uv),quads[in.index]);
}
fragment float4 stn_present(VOut in [[stage_in]], constant Quad &q [[buffer(0)]],
    texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_zero,filter::nearest);
    float4 c=image.sample(s,in.uv);
    if (!q.linear) return c;
    if (c.a<=0) return float4(0);
    float3 straight=c.rgb/c.a;
    float L=max(0.0f,max(straight.r,max(straight.g,straight.b)));
    float H=max(1.0f,q.options.w), K=min(1.0f,0.75f*H);
    if (L>K) straight*=(K+(H-K)*(L-K)/((L-K)+(H-K)))/L;
    if (!q.sourceLinear) straight=encodeSRGB(straight);
    return float4(straight*c.a,c.a);
}

