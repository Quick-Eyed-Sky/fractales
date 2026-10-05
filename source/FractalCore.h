// Fractales -- high-precision core, in plain C so it builds with Apple's command line tools
// and can be tested anywhere.
//
// The GPU only has 32-bit floats, which run out of digits after a zoom of about x100 000.
// Deep zooms therefore use "perturbation": one point of the view (the reference) is iterated
// here on the CPU with as many digits as the zoom needs, and the GPU only iterates the tiny
// difference between each pixel and that reference, which fits in a float.
//
// Numbers are signed fixed point: FC_MAX_LIMBS 32-bit limbs, little-endian, two's complement.
// The top limb is the integer part, the others the fraction (480 bits, about 144 decimal digits).
// Functions taking `nl` only use the top `nl` limbs (the lower ones are ignored and written as
// zero), so the same number can be computed fast at low precision or slowly at high precision.

#ifndef FRACTAL_CORE_H
#define FRACTAL_CORE_H

#include <stdint.h>
#include <stddef.h>

#define FC_MAX_LIMBS 16

typedef struct fc_num {
    uint32_t d[FC_MAX_LIMBS];
} fc_num;

// Fractal formulas, shared with Shaders.metal (keep the numbers in sync).
enum {
    FC_MANDELBROT = 0,   // z^2 + c
    FC_BURNING_SHIP = 1, // (|x| + i|y|)^2 + c
    FC_TRICORN = 2,      // conj(z)^2 + c
    FC_MULTIBROT3 = 3,   // z^3 + c
    FC_CELTIC = 4,       // |x^2 - y^2| + 2ixy + c
    FC_FORMULA_COUNT = 5
};

// Parameters of the GPU passes, laid out exactly as FractalParams and ColorParams in
// Shaders.metal (plain 4-byte fields, so C, Swift and Metal agree). Field meanings are there.
typedef struct fc_gpu_params {
    float offsetX, offsetY, pixelSize, ySign;
    uint32_t fullWidth, fullHeight, originX, originY, width, height;
    uint32_t maxIter, formula, julia, lenA, lenB;
    float bailout2, logPower;
} fc_gpu_params;

typedef struct fc_color_params {
    float density, offset, insideR, insideG, insideB;
} fc_color_params;

// Limbs needed so that a pixel of `pixelSize` (complex units) keeps about 32 bits of margin.
int fc_limbs_for_pixel_size(double pixelSize);

void fc_zero(fc_num *a);
void fc_from_double(fc_num *out, double x);
double fc_to_double(const fc_num *a);
// Parses a decimal such as "-0.7436438870371587" (no exponent). Returns 0 on bad input.
int fc_parse(fc_num *out, const char *s);
// Writes the number in decimal with `digits` digits after the point. Returns the length.
int fc_to_string(const fc_num *a, int digits, char *buf, size_t bufSize);

void fc_add(fc_num *out, const fc_num *a, const fc_num *b, int nl);
void fc_sub(fc_num *out, const fc_num *a, const fc_num *b, int nl);
void fc_mul(fc_num *out, const fc_num *a, const fc_num *b, int nl);
void fc_neg(fc_num *out, const fc_num *a, int nl);
void fc_abs(fc_num *out, const fc_num *a, int nl);
// a += x, exactly (x is converted with all its bits, at full precision).
void fc_add_double(fc_num *a, double x);
// (a - b) as a double: exact enough for the small offsets between the view and the reference.
double fc_diff_to_double(const fc_num *a, const fc_num *b);

// Iterates `formula` from z0 with constant c at `nl` limbs and writes the orbit as float pairs
// (re, im) into `out`, which must hold 2 * (maxIter + 1) floats. Stops after the first point
// with |z|^2 > bailout2 (that point is stored too) or after maxIter steps.
// Returns the number of points stored, always at least 2.
int fc_orbit(int formula, const fc_num *z0re, const fc_num *z0im,
             const fc_num *cre, const fc_num *cim,
             int nl, int maxIter, double bailout2, float *out);

// ---- Previews and the automatic voyage (Voyage.c) ----

// Escape counts of a small picture, computed directly in double precision (enough for the
// ready-made figures): the same smooth count as the GPU, -1 inside the set, row 0 at the top.
// (cx, cy) is the centre; with `julia`, z0 is the pixel and c is (kx, ky).
void fc_preview(int formula, int julia, double kx, double ky, double cx, double cy,
                double halfHeight, double ySign, int w, int h, int maxIter, float *out);

// State of the automatic voyage. Offsets are in complex units from the view centre, oriented as
// on screen (+y up), like the moves the voyage asks for.
typedef struct fc_voyage {
    double targetX, targetY;  // where it heads
    int hasTarget;
    int backing;              // 0 diving; 1 backing out of a dead end; 2 climbing back after the deepest zoom
    double backUntil;         // half height to climb back to
    int fresh;                // the next look chooses freely (start, or after climbing back)
    double lastScore;         // best cell score of the last look (0: nothing to see)
    uint32_t seed;
} fc_voyage;

void fc_voyage_start(fc_voyage *v, uint32_t seed);

// How interesting one cell of a grid of escape counts is (0: empty or black). Used by
// fc_voyage_look; exposed for the tests.
double fc_voyage_cell_score(const float *samples, int w, int h, int x0, int y0, int cw, int ch);

// Looks at a w x h grid of escape counts (-1 inside, row 0 at the top) sampled evenly over a
// picture whose half height was `probeHalf` and whose centre was (ox, oy) from the current view
// centre, and chooses where to head. `halfHeight` is the current half height; `minHalf` the
// deepest the engine can go, `maxHalf` how far out it may climb.
void fc_voyage_look(fc_voyage *v, const float *samples, int w, int h,
                    double ox, double oy, double probeHalf,
                    double halfHeight, double minHalf, double maxHalf);

// Advances the voyage by dt seconds at `rate` (natural log of the zoom per second). Writes how
// far to move the view centre and returns the factor to multiply the half height by.
double fc_voyage_step(fc_voyage *v, double dt, double rate, double halfHeight,
                      double *moveX, double *moveY);

#endif
