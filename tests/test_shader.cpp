// Runs the GPU kernel of Shaders.metal on the CPU (through tests/shim/metal_stdlib) and checks
// it against a direct iteration in 113-bit __float128, at shallow and deep zooms, for every
// formula. Also writes a few pictures (PGM) to look at.
//
//   g++ -O2 -std=c++17 -Itests/shim -Isource tests/test_shader.cpp source/FractalCore.c -lquadmath -o /tmp/ts && /tmp/ts [outdir]
#include "FractalCore.h"
#include <quadmath.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include "../source/Shaders.metal"
#undef kernel
#undef vertex
#undef fragment
#undef device
#undef constant

using namespace metal;

#include <cstddef>
// The app fills the C structs; the shader reads its own copies. They must match field for field.
static_assert(sizeof(FractalParams) == sizeof(fc_gpu_params), "FractalParams size");
static_assert(offsetof(FractalParams, lenB) == offsetof(fc_gpu_params, lenB), "FractalParams layout");
static_assert(offsetof(FractalParams, logPower) == offsetof(fc_gpu_params, logPower), "FractalParams layout");
static_assert(sizeof(ColorParams) == sizeof(fc_color_params), "ColorParams size");


static __float128 to_q(const fc_num &a) {
    fc_num m; int neg = (a.d[FC_MAX_LIMBS - 1] >> 31) != 0;
    fc_abs(&m, &a, FC_MAX_LIMBS);
    __float128 v = 0;
    for (int i = FC_MAX_LIMBS - 1; i >= FC_MAX_LIMBS - 6; i--) v += ldexpq((__float128)m.d[i], 32 * (i - (FC_MAX_LIMBS - 1)));
    return neg ? -v : v;
}

struct View {
    int formula; bool julia; fc_num cx, cy; double kx, ky; double halfHeight; int maxIter;
};

static const float kBailout2 = 65536.0f;

// What the app does: reference at the view centre, orbit A (+ B for Julia), then the kernel.
static std::vector<float> renderPerturbed(const View &v, int w, int h) {
    double pixelSize = 2.0 * v.halfHeight / h;
    int nl = fc_limbs_for_pixel_size(pixelSize);
    std::vector<float> A(2 * (v.maxIter + 1)), B;
    fc_num zero; fc_zero(&zero);
    fc_num kx, ky; fc_from_double(&kx, v.kx); fc_from_double(&ky, v.ky);
    int lenA, lenB;
    if (v.julia) {
        lenA = fc_orbit(v.formula, &v.cx, &v.cy, &kx, &ky, nl, v.maxIter, kBailout2, A.data());
        B.resize(A.size());
        lenB = fc_orbit(v.formula, &zero, &zero, &kx, &ky, nl, v.maxIter, kBailout2, B.data());
    } else {
        lenA = fc_orbit(v.formula, &zero, &zero, &v.cx, &v.cy, nl, v.maxIter, kBailout2, A.data());
        B = A; lenB = lenA;
    }
    FractalParams p{};
    p.offsetX = 0; p.offsetY = 0; p.pixelSize = (float)pixelSize;
    p.ySign = v.formula == FC_BURNING_SHIP ? -1.0f : 1.0f;
    p.fullWidth = w; p.fullHeight = h; p.originX = 0; p.originY = 0; p.width = w; p.height = h;
    p.maxIter = v.maxIter; p.formula = v.formula; p.julia = v.julia; p.lenA = lenA; p.lenB = lenB;
    p.bailout2 = kBailout2; p.logPower = std::log(v.formula == FC_MULTIBROT3 ? 3.0f : 2.0f);
    std::vector<float> pixels(4 * w * h);
    texture2d<float, access::write> tex; tex.w = w; tex.h = h; tex.data = pixels.data();
    for (uint y = 0; y < (uint)h; y++)
        for (uint x = 0; x < (uint)w; x++)
            iterate(p, (const float2 *)A.data(), (const float2 *)B.data(), tex, uint2{x, y});
    std::vector<float> r(w * h);
    for (int i = 0; i < w * h; i++) r[i] = pixels[4 * i];
    return r;
}

template <class T> static T qabs(T v) { return v < 0 ? -v : v; }

template <class Q> static std::vector<float> renderDirectT(const View &v, int w, int h) {
    Q pixelSize = (Q)2 * v.halfHeight / h, cx = (Q)to_q(v.cx), cy = (Q)to_q(v.cy);
    Q ySign = v.formula == FC_BURNING_SHIP ? -1 : 1;
    double logPower = std::log(v.formula == FC_MULTIBROT3 ? 3.0 : 2.0);
    std::vector<float> r(w * h);
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) {
            Q px = (Q)i + (Q)0.5 - (Q)0.5 * w, py = (Q)0.5 * h - ((Q)j + (Q)0.5);
            Q pr = cx + px * pixelSize, pi = cy + py * ySign * pixelSize;
            Q x, y, ar, ai;
            if (v.julia) { x = pr; y = pi; ar = v.kx; ai = v.ky; } else { x = 0; y = 0; ar = pr; ai = pi; }
            float res = -1;
            for (int n = 0; n < v.maxIter; n++) {
                Q x2 = x * x, y2 = y * y, xy = x * y, nx, ny;
                switch (v.formula) {
                case FC_BURNING_SHIP: nx = x2 - y2; ny = 2 * qabs(xy); break;
                case FC_TRICORN: nx = x2 - y2; ny = -2 * xy; break;
                case FC_MULTIBROT3: nx = x * (x2 - 3 * y2); ny = y * (3 * x2 - y2); break;
                case FC_CELTIC: nx = qabs(x2 - y2); ny = 2 * xy; break;
                default: nx = x2 - y2; ny = 2 * xy; break;
                }
                x = nx + ar; y = ny + ai;
                double r2 = (double)(x * x + y * y);
                if (r2 > kBailout2) { res = std::max(0.0, n + 1 - std::log(0.5 * std::log(r2)) / logPower); break; }
            }
            r[j * w + i] = res;
        }
    return r;
}

static std::vector<float> renderDirect(const View &v, int w, int h) { return renderDirectT<__float128>(v, w, h); }

static void writePGM(const std::string &path, const std::vector<float> &img, int w, int h) {
    FILE *f = fopen(path.c_str(), "wb"); if (!f) return;
    fprintf(f, "P5\n%d %d\n255\n", w, h);
    for (float v : img) { unsigned char c = v < 0 ? 0 : (unsigned char)(40 + 215 * (0.5 + 0.5 * std::sin(std::sqrt(v) * 1.3))); fputc(c, f); }
    fclose(f);
}

// Share of pixels that disagree. Near the boundary the escape count is chaotic: even double
// precision disagrees with 113 bits on a few percent of single pixels. So the counts are first
// smoothed with a 3x3 median, then compared with a tolerance of 1 + 10%.
static std::vector<float> median3(const std::vector<float> &a, int w, int h) {
    std::vector<float> r(a.size());
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) {
            float v[9]; int n = 0;
            for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++)
                v[n++] = a[std::min(h - 1, std::max(0, j + dj)) * w + std::min(w - 1, std::max(0, i + di))];
            std::nth_element(v, v + 4, v + 9);
            r[j * w + i] = v[4];
        }
    return r;
}

static double mismatch(const std::vector<float> &a0, const std::vector<float> &b0, int w, int h) {
    std::vector<float> a = median3(a0, w, h), b = median3(b0, w, h);
    int bad = 0;
    for (size_t i = 0; i < a.size(); i++) {
        bool ia = a[i] < 0, ib = b[i] < 0;
        if (ia != ib || (!ia && std::fabs(a[i] - b[i]) > 1.0f + 0.1f * b[i])) bad++;
    }
    return (double)bad / a.size();
}

static double outsideShare(const std::vector<float> &a) {
    int n = 0; for (float v : a) n += v >= 0; return (double)n / a.size();
}

// Moves the view towards the escaping pixel with the highest count, the way a dive heads
// for a miniature copy of the set.
static void zoomTowardsDetail(View &v, const std::vector<float> &img, int w, int h, double factor) {
    int best = -1; double bestScore = -1;
    for (int j = h / 4; j < 3 * h / 4; j++)
        for (int i = w / 4; i < 3 * w / 4; i++) {
            float c = img[j * w + i];
            if (c >= 0 && c > bestScore) { bestScore = c; best = j * w + i; }
        }
    if (best >= 0) {
        int i = best % w, j = best / w;
        double pixelSize = 2.0 * v.halfHeight / h;
        double ySign = v.formula == FC_BURNING_SHIP ? -1 : 1;
        fc_add_double(&v.cx, (i + 0.5 - 0.5 * w) * pixelSize);
        fc_add_double(&v.cy, (0.5 * h - (j + 0.5)) * ySign * pixelSize);
    }
    v.halfHeight /= factor;
}

static int failures = 0;

static void check(const char *name, View v, int w, int h, double maxMismatch, const char *outdir) {
    std::vector<float> a = renderPerturbed(v, w, h), b = renderDirect(v, w, h);
    double mm = mismatch(a, b, w, h), out = outsideShare(b);
    bool ok = mm <= maxMismatch && out > 0.02;
    if (!ok) failures++;
    char cxs[80]; fc_to_string(&v.cx, 34, cxs, sizeof cxs);
    printf("%s %-28s half-height %.1e  iterations %5d  mismatch %.2f%%  escaping %.0f%%  (x %s)\n",
           ok ? "ok  " : "FAIL", name, v.halfHeight, v.maxIter, 100 * mm, 100 * out, cxs);
    if (outdir) {
        writePGM(std::string(outdir) + "/" + name + "-gpu.pgm", a, w, h);
        writePGM(std::string(outdir) + "/" + name + "-ref.pgm", b, w, h);
    }
}

static View makeView(int formula, bool julia, const char *x, const char *y, double half, int iters, double kx = 0, double ky = 0) {
    View v; v.formula = formula; v.julia = julia; fc_parse(&v.cx, x); fc_parse(&v.cy, y);
    v.kx = kx; v.ky = ky; v.halfHeight = half; v.maxIter = iters; return v;
}

int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : nullptr;
    const int W = 96, H = 72;
    // Shallow views of every formula. The tolerance is 3% because even double precision
    // disagrees with 113 bits on about 2% of the chaotic Burning Ship pixels.
    check("mandelbrot", makeView(FC_MANDELBROT, false, "-0.6", "0", 1.3, 300), W, H, 0.03, outdir);
    check("burning-ship", makeView(FC_BURNING_SHIP, false, "-0.45", "-0.5", 1.2, 300), W, H, 0.03, outdir);
    check("tricorn", makeView(FC_TRICORN, false, "-0.3", "0", 1.4, 300), W, H, 0.03, outdir);
    check("multibrot3", makeView(FC_MULTIBROT3, false, "0", "0", 1.3, 300), W, H, 0.03, outdir);
    check("celtic", makeView(FC_CELTIC, false, "-0.5", "0", 1.4, 300), W, H, 0.03, outdir);
    check("julia-rabbit", makeView(FC_MANDELBROT, true, "0", "0", 1.3, 300, -0.123, 0.745), W, H, 0.03, outdir);
    check("julia-dendrite", makeView(FC_MANDELBROT, true, "0", "0", 1.3, 300, 0, 1), W, H, 0.03, outdir);

    // Deep zooms, far past what a float can do directly (it gives up near 1e-6).
    struct Dive { const char *name; View v; double deepest; };
    Dive dives[] = {
        {"deep-mandelbrot", makeView(FC_MANDELBROT, false, "-0.7436438870371587", "0.1318259042053119", 1e-4, 1500), 1e-27},
        {"deep-burning-ship", makeView(FC_BURNING_SHIP, false, "-1.7623", "-0.0278", 3e-3, 1500), 1e-20},
        {"deep-tricorn", makeView(FC_TRICORN, false, "-0.3", "0.9", 0.3, 1200), 1e-16},
        {"deep-multibrot3", makeView(FC_MULTIBROT3, false, "-0.5", "0.6", 0.2, 1200), 1e-16},
        {"deep-celtic", makeView(FC_CELTIC, false, "-0.4", "0.6", 0.2, 1200), 1e-16},
        {"deep-julia", makeView(FC_MANDELBROT, true, "0", "0", 1.0, 1200, -0.7269, 0.1889), 1e-20},
    };
    for (Dive &d : dives) {
        View v = d.v;
        while (v.halfHeight > d.deepest) {
            std::vector<float> img = renderPerturbed(v, W, H);
            zoomTowardsDetail(v, img, W, H, 8.0);
            v.maxIter += 60;
        }
        check(d.name, v, W, H, 0.05, outdir);
    }
    printf(failures ? "%d FAILURES\n" : "all shader tests passed\n", failures);
    return failures != 0;
}
