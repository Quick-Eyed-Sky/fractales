// Fractales -- GPU shaders.
//
// Pass 1, `iterate` (compute): for every pixel, the smooth escape count, or -1 inside the set,
// into a 32-bit float texture. It only runs again when the view changes.
// `probe` (compute): copies a small grid of those counts for the automatic voyage.
// Pass 2, `colorVertex` / `colorFragment`: turns those counts into colours through a palette,
// so changing colours costs nothing.
//
// Pass 1 uses perturbation with rebasing: the CPU gives one reference orbit Z (FractalCore.c)
// and every pixel iterates only its tiny difference d from it, z = Z + d, which a 32-bit float
// holds at any zoom. When z comes closer to 0 than d is large, or the reference runs out, the
// pixel restarts ("rebases") on orbit B, which starts at the critical point 0. For the
// Mandelbrot-like formulas A and B are the same orbit; for Julia sets A starts at the view
// centre and B at 0.
//
// This file is compiled by the app at launch (MTLDevice.makeLibrary(source:)), so building
// needs no Xcode. Keep FractalParams identical to the Swift struct of the same name: plain
// 4-byte fields only, so the layout is the same on both sides.

#include <metal_stdlib>
using namespace metal;

struct FractalParams {
    float offsetX;      // view centre minus reference point, complex units
    float offsetY;
    float pixelSize;    // complex units per pixel of the full image
    float ySign;        // +1: up on screen is +i; -1: flipped (Burning Ship stands upright)
    uint  fullWidth;    // whole image, in pixels
    uint  fullHeight;
    uint  originX;      // where this texture starts within the whole image (tiled renders)
    uint  originY;
    uint  width;        // this texture
    uint  height;
    uint  maxIter;
    uint  formula;      // FC_* in FractalCore.h
    uint  julia;        // 0: c varies per pixel; 1: z0 varies per pixel, c fixed
    uint  lenA;         // points in orbit A (>= 2)
    uint  lenB;         // points in orbit B (>= 2)
    float bailout2;     // escape when |z|^2 is larger
    float logPower;     // log(degree), for the smooth count
};

static inline float2 cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// |c + d| - |c|, without losing the digits of a small d against a large c.
static inline float diffabs(float c, float d) {
    float cd = c + d;
    if (c >= 0.0f) {
        return cd >= 0.0f ? d : -(2.0f * c + d);
    } else {
        return cd > 0.0f ? (2.0f * c + d) : -d;
    }
}

// One step of the difference: given Z_n and d_n, returns d_{n+1} = f(Z_n + d_n) - f(Z_n) + dc.
static inline float2 perturbStep(uint formula, float2 Z, float2 d, float2 dc) {
    float X = Z.x, Y = Z.y, a = d.x, b = d.y;
    switch (formula) {
    case 1: { // Burning Ship
        float re = (2.0f * X + a) * a - (2.0f * Y + b) * b;
        float im = 2.0f * diffabs(X * Y, X * b + a * (Y + b));
        return float2(re, im) + dc;
    }
    case 2: { // Tricorn
        float2 t = cmul(2.0f * Z + d, d);
        return float2(t.x, -t.y) + dc;
    }
    case 3: { // Multibrot z^3: (Z+d)^3 - Z^3 = d (3Z^2 + 3Zd + d^2)
        float2 t = 3.0f * cmul(Z, Z) + 3.0f * cmul(Z, d) + cmul(d, d);
        return cmul(d, t) + dc;
    }
    case 4: { // Celtic
        float re = diffabs(X * X - Y * Y, (2.0f * X + a) * a - (2.0f * Y + b) * b);
        float im = 2.0f * (X * b + a * (Y + b));
        return float2(re, im) + dc;
    }
    default: // Mandelbrot: (Z+d)^2 - Z^2 = (2Z + d) d
        return cmul(2.0f * Z + d, d) + dc;
    }
}

kernel void iterate(constant FractalParams &p [[buffer(0)]],
                    const device float2 *orbitA [[buffer(1)]],
                    const device float2 *orbitB [[buffer(2)]],
                    texture2d<float, access::write> out [[texture(0)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= p.width || gid.y >= p.height) return;

    // Pixel centre relative to the image centre, in pixels, +y up.
    float px = float(gid.x + p.originX) + 0.5f - 0.5f * float(p.fullWidth);
    float py = 0.5f * float(p.fullHeight) - (float(gid.y + p.originY) + 0.5f);
    float2 offset = float2(p.offsetX + px * p.pixelSize, p.offsetY + py * p.ySign * p.pixelSize);

    float2 dc = p.julia != 0 ? float2(0.0f) : offset;
    float2 d  = p.julia != 0 ? offset : float2(0.0f);
    const device float2 *Z = orbitA;
    uint len = p.lenA;
    uint m = 0;
    float result = -1.0f;

    for (uint n = 0; n < p.maxIter; n++) {
        if (m + 1 >= len) {           // the reference ran out: continue on orbit B from its start
            d = Z[m] + d - orbitB[0];
            Z = orbitB; len = p.lenB; m = 0;
        }
        d = perturbStep(p.formula, Z[m], d, dc);
        m++;
        float2 z = Z[m] + d;
        float r2 = dot(z, z);
        if (r2 > p.bailout2) {
            // Smooth count: n + 1 - log(log|z|) / log(degree).
            result = float(n + 1) - log(0.5f * log(r2)) / p.logPower;
            result = max(result, 0.0f);
            break;
        }
        if (r2 < dot(d, d)) {         // z passed closer to 0 than d is large: rebase on B
            d = z - orbitB[0];
            Z = orbitB; len = p.lenB; m = 0;
        }
    }
    out.write(float4(result, 0.0f, 0.0f, 0.0f), gid);
}

// ---- Probe for the automatic voyage ----

// Copies an evenly spaced grid of escape counts (size.x by size.y, row 0 at the top) out of
// the counts texture, for the voyage to read on the CPU (Voyage.c). Each sample is the texel
// at the centre of its grid cell.
kernel void probe(texture2d<float, access::read> counts [[texture(0)]],
                  device float *out [[buffer(0)]],
                  constant uint2 &size [[buffer(1)]],
                  uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= size.x || gid.y >= size.y) return;
    uint w = counts.get_width(), h = counts.get_height();
    uint x = min((2 * gid.x + 1) * w / (2 * size.x), w - 1);
    uint y = min((2 * gid.y + 1) * h / (2 * size.y), h - 1);
    out[gid.y * size.x + gid.x] = counts.read(uint2(x, y)).r;
}

// ---- Colouring ----

struct ColorParams {
    float density;      // palette cycles per unit of sqrt(count)
    float offset;       // palette shift, 0...1
    float insideR;      // colour of the inside of the set
    float insideG;
    float insideB;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut colorVertex(uint vid [[vertex_id]]) {
    // One triangle that covers the whole view.
    float2 pos = float2(vid == 2 ? 3.0f : -1.0f, vid == 1 ? 3.0f : -1.0f);
    VertexOut o;
    o.position = float4(pos, 0.0f, 1.0f);
    o.uv = float2(0.5f * (pos.x + 1.0f), 0.5f * (1.0f - pos.y));
    return o;
}

fragment float4 colorFragment(VertexOut in [[stage_in]],
                              constant ColorParams &c [[buffer(0)]],
                              texture2d<float> counts [[texture(0)]],
                              texture2d<float> palette [[texture(1)]])
{
    constexpr sampler nearest(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr sampler smooth(coord::normalized, address::repeat, filter::linear);
    float v = counts.sample(nearest, in.uv).r;
    if (v < 0.0f) return float4(c.insideR, c.insideG, c.insideB, 1.0f);
    float t = fract(sqrt(v) * c.density + c.offset);
    return float4(palette.sample(smooth, float2(t, 0.5f)).rgb, 1.0f);
}
