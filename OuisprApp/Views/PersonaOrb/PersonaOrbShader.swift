// OuisprApp/Views/PersonaOrb/PersonaOrbShader.swift
// The character orb's Metal source, compiled on the device at first use.

/// The Metal Shading Language source of the orb: a port of the bench's WebGL shader
/// (direction "Personnage", variant "Fidèle", 23 Nov 2026), same layers and constants.
///
/// WHY source compiled at run time and not a `.metal` file: since Xcode 26 the Metal
/// compiler is a separate download (`xcodebuild -downloadComponent MetalToolchain`),
/// absent from a fresh Xcode and from CI runners. Compiling this one small shader on
/// the device takes a few milliseconds once per launch, and the build needs nothing
/// beyond Xcode itself.
enum PersonaOrbShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

namespace {
constant float R = 0.50;

// smoothstep that accepts edge0 > edge1, as the GLSL original relies on (undefined in MSL).
float ss(float e0, float e1, float x) {
    float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }
float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
float sq(float x) { return x * x; }

float3 rainbow(float a) {
    float k = fract(a / 6.2831853) * 8.0;
    float3 c = float3(0.96, 0.24, 0.38);
    c = mix(c, float3(1.0, 0.30, 0.16), clamp(k, 0.0, 1.0));
    c = mix(c, float3(1.0, 0.56, 0.14), clamp(k - 1.0, 0.0, 1.0));
    c = mix(c, float3(0.96, 0.86, 0.26), clamp(k - 2.0, 0.0, 1.0));
    c = mix(c, float3(0.55, 0.90, 0.40), clamp(k - 3.0, 0.0, 1.0));
    c = mix(c, float3(0.14, 0.80, 0.84), clamp(k - 4.0, 0.0, 1.0));
    c = mix(c, float3(0.14, 0.46, 1.0), clamp(k - 5.0, 0.0, 1.0));
    c = mix(c, float3(0.50, 0.30, 1.0), clamp(k - 6.0, 0.0, 1.0));
    c = mix(c, float3(0.96, 0.24, 0.38), clamp(k - 7.0, 0.0, 1.0));
    return c;
}

float eyeSD(float2 q, float2 c, float hh, float rr, float tilt, float fx) {
    float2 v = rot(q - c, tilt);
    v.x /= fx;
    v.y -= clamp(v.y, -hh, hh);
    return length(v) - rr;
}

// A small circle on the sphere facing n, projected as an ellipse. Returns the signed
// distance to it and, in zf, the depth of the nearest ring point (1 = facing us).
float ringD(float2 p, float3 n, float h, thread float &zf) {
    n = normalize(n);
    float3 c = n * h;
    float r = sqrt(R * R - h * h);
    float l = length(n.xy);
    float2 major = l > 1e-4 ? float2(-n.y, n.x) / l : float2(1.0, 0.0);
    float2 minor = float2(-major.y, major.x);
    float a = r, b = max(r * abs(n.z), 1e-3);
    float2 q = p - c.xy;
    float2 qq = float2(dot(q, major), dot(q, minor));
    float2 e = qq / float2(a, b);
    float le = max(length(e), 1e-4);
    float d = (le - 1.0) * le / max(length(qq / float2(a * a, b * b)), 1e-4);
    float t = atan2(e.y, e.x);
    float3 V = cross(n, float3(major, 0.0));
    zf = (c.z + r * sin(t) * V.z) / R;
    return d;
}

float fil(float d, float a) { return 0.94 + 0.06 * sin(d * 260.0 + sin(a * 3.0) * 2.0); }
}

struct OrbUniforms { float4 a; float4 b; float4 c; float4 d; float2 size; };
struct OrbVertexOut { float4 position [[position]]; };

vertex OrbVertexOut personaOrbVertex(uint vid [[vertex_id]]) {
    // One triangle that covers the screen.
    float2 uv = float2((vid << 1) & 2, vid & 2);
    OrbVertexOut out;
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment half4 personaOrbFragment(OrbVertexOut in [[stage_in]], constant OrbUniforms &u [[buffer(0)]]) {
    float2 position = in.position.xy, size = u.size;
    float4 a = u.a, b = u.b, c = u.c, d = u.d;

    float uPhase = a.x, uSpin = a.y;
    float2 g = a.zw, gl = b.xy;
    float uBlink = b.z, uOpen = b.w, uSquint = c.x, uBob = c.y, uSwirl = c.z, uSquash = c.w;
    float uGlow = d.x, uLevel = d.y, uGhost = d.z, scale = d.w;

    // Same units as the bench (orb radius 0.5), the orb filling 86 % of the frame, y up.
    float2 p = (position - 0.5 * size) / (0.5 * min(size.x, size.y)) * 0.58;
    p.y = -p.y;
    p.x /= (1.0 + uSquash);
    p.y *= (1.0 + uSquash);
    float2 px = floor(position * scale);

    float L = length(p);
    float body = ss(0.006, -0.006, L - R);
    float id = length(p - g * 0.10) / R;
    float3 inC = mix(float3(0.06, 0.40, 0.29), float3(0.02, 0.17, 0.16), ss(0.0, 1.0, id));
    inC = mix(inC, float3(0.01, 0.07, 0.08), ss(0.78, 1.02, id));
    inC += (hash(px) - 0.5) * 0.045;
    inC += 0.012 * (0.5 + 0.5 * sin((p.x * 0.6 + p.y) * 230.0));
    // A little more see-through at the centre (Alex, bench of 23 Nov 2026).
    float alpha = body * (0.72 + 0.28 * ss(0.0, 0.75, id));
    float3 col = inC * uGlow * alpha;

    float wob = 0.30 * sin(uSpin * 0.8) + 0.12 * sin(uSpin * 1.7);
    float sa = atan2(p.y, p.x) + wob - 0.55;
    float3 rcol = rainbow(sa) * (0.84 + 0.16 * sin(sa - 0.4));
    float grain = hash(floor(px * 0.5) + 3.1) - 0.5;

    // Glass shell: light gathering towards the edge, a cool pool at the bottom, a bloom outside.
    col += rcol * exp((L - R) / 0.085) * body * 0.22 * uGlow;
    col += float3(0.04, 0.52, 0.78) * body * ss(-0.05, -0.95, p.y / R) * exp((L - R) / 0.20) * 0.62 * uGlow;
    col += rcol * exp(-max(L - R, 0.0) / 0.03) * (1.0 - body) * 0.16 * uGlow;

    // Silk sheets: a crisp edge and a long soft fade, each trailing the gaze by its own amount.
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float2 pk = p - gl * (0.05 + 0.04 * fk);
        float2 q = rot(pk, 0.55 * sin(uSpin * 0.7 + fk * 2.3) + 0.35 + fk * 2.4);
        float e = 0.34 + 0.16 * sin(uPhase * 0.5 + fk * 1.9);
        float de = (length(float2(q.x, q.y / e)) - R * 0.94) * e;
        float side = ss(0.004, -0.004, de) * body * ss(0.35, -0.55, q.y / R);
        float crisp = exp(de / 0.032), soft = exp(de / 0.12) * 0.22;
        float3 sc = mix(float3(0.10, 0.78, 0.80), rainbow(atan2(q.y, q.x) + wob), 0.35);
        col += sc * side * (crisp + soft) * (0.10 + 0.38 * uSwirl) * (1.0 + 0.6 * grain);
    }

    // A dark fold, so the inside reads as depth rather than a flat disc.
    float2 qf = rot(p - gl * 0.07, -0.9 + 0.5 * sin(uSpin * 0.6));
    float df = (length(float2(qf.x, qf.y / 0.42)) - R * 0.80) * 0.42;
    col *= 1.0 - 0.38 * ss(0.004, -0.004, df) * exp(df / 0.05) * body * ss(0.1, -0.6, qf.y / R) * (0.4 + 0.6 * uSwirl);

    // The ring and two finer strands that follow it with a lag.
    float2 g2 = gl + (gl - g) * 0.8;
    float z0, z1, z2;
    float pw = 0.07 + 0.20 * uSwirl + 0.22 * uLevel;
    float2 w0 = pw * float2(sin(uSpin * 0.9), sin(uSpin * 1.3 + 0.8));
    float2 w1 = pw * 1.35 * float2(sin(uSpin * 0.9 - 0.9), sin(uSpin * 1.3 - 0.2));
    float2 w2 = pw * 1.70 * float2(sin(uSpin * 0.7 + 1.6), sin(uSpin * 1.1 + 2.0));
    float d0 = ringD(p, float3(g * 0.80 + w0, 1.0), R * 0.46, z0);
    float d1 = ringD(p, float3(gl * 0.80 + w1, 1.0), R * 0.50, z1);
    float d2 = ringD(p, float3(g2 * 0.80 + w2, 1.0), R * 0.42, z2);
    float th = (1.0 + 0.55 * uLevel) * (1.0 + 0.30 * ss(-0.2, 0.9, p.y / max(L, 1e-3)));
    col *= 1.0 - 0.30 * exp(-sq((d0 + 0.105 * th) / 0.03)) * body;
    float prof = d0 > 0.0 ? exp(-sq(d0 / (0.034 * th))) : exp(-sq(d0 / (0.085 * th)));
    prof = clamp(prof * fil(d0, sa) * (0.75 + 0.25 * z0) * 1.05, 0.0, 1.0);
    col = mix(col, rcol * uGlow * (1.0 + 0.10 * grain), prof);
    alpha = mix(alpha, 1.0, prof * body);
    float spread = clamp(length(g - gl) * 4.0 + 0.5 * uSwirl + 0.6 * uLevel, 0.0, 1.0) * uGhost;
    float s1 = (exp(-sq(d1 / 0.009)) * 0.55 + exp(-sq(d1 / 0.030)) * 0.18) * (0.35 + 0.65 * spread);
    float s2 = (exp(-sq(d2 / 0.007)) * 0.45 + exp(-sq(d2 / 0.026)) * 0.14) * (0.20 + 0.80 * spread);
    float inside = step(L, R + 0.03);
    col += rainbow(sa + 0.25) * s1 * fil(d1, sa) * uGlow * inside;
    col += rainbow(sa - 0.30) * s2 * uGlow * inside;

    // Eyes.
    float sp = 0.105 * (1.0 - 0.28 * abs(g.x));
    float2 ec = g * 0.16 + float2(0.0, uBob);
    float rr = mix(0.027, 0.019, clamp(uSquint, 0.0, 1.2));
    float hh = max(0.050 * uOpen * (1.0 - uBlink) * (1.0 - uSquint), 0.0);
    float tilt = -g.x * 0.35, fx = 1.0 - 0.25 * abs(g.x);
    float eye = min(eyeSD(p, ec + float2(-sp, 0.0), hh, rr, tilt, fx), eyeSD(p, ec + float2(sp, 0.0), hh, rr, tilt, fx));
    float eyeMask = ss(0.004, -0.004, eye);
    col = mix(col, float3(1.0, 1.0, 0.98), eyeMask);
    alpha = mix(alpha, 1.0, eyeMask);
    col += float3(0.6, 1.0, 0.9) * exp(-max(eye, 0.0) / 0.02) * 0.16 * body;

    return half4(half3(max(col, 0.0)), half(clamp(alpha, 0.0, 1.0)));
}
"""#
}
