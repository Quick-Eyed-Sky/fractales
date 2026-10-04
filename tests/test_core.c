// Tests for FractalCore.c, checked against GCC's 128-bit __float128 (113-bit mantissa).
//   gcc -O2 -Wall -Isource tests/test_core.c source/FractalCore.c -lquadmath -lm && ./a.out
#include "FractalCore.h"
#include <quadmath.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static __float128 to_q(const fc_num *a) { // exact enough: top 5 limbs
    fc_num m; int neg = (a->d[FC_MAX_LIMBS-1] >> 31) != 0;
    fc_abs(&m, a, FC_MAX_LIMBS);
    __float128 v = 0;
    for (int i = FC_MAX_LIMBS-1; i >= FC_MAX_LIMBS-6; i--) v += ldexpq((__float128)m.d[i], 32*(i-(FC_MAX_LIMBS-1)));
    return neg ? -v : v;
}

static double rnd(void) { return (double)rand() / RAND_MAX * 4.0 - 2.0; }

int main(void) {
    fc_num a, b, c;
    // Round trips.
    double vals[] = {0, 1, -1, 0.5, -0.75, 1.0/3.0, -2.25e-12, 3.0e-30, -1.7e-300, 1234.5678};
    for (unsigned i = 0; i < sizeof vals/sizeof *vals; i++) {
        fc_from_double(&a, vals[i]);
        double back = fc_to_double(&a);
        double expect = fabs(vals[i]) < 1e-140 ? 0 : vals[i];
        CHECK(back == expect, "round trip %g -> %.17g", vals[i], back);
    }
    // Parse and print.
    CHECK(fc_parse(&a, "-0.743643887037158704752191506114774"), "parse");
    char buf[128];
    fc_to_string(&a, 33, buf, sizeof buf);
    CHECK(strcmp(buf, "-0.743643887037158704752191506114774") == 0 || strncmp(buf, "-0.7436438870371587047521915061147", 34) == 0, "print %s", buf);
    CHECK(fabs(fc_to_double(&a) + 0.7436438870371587) < 1e-16, "parse value %.17g", fc_to_double(&a));
    CHECK(!fc_parse(&a, "abc") && !fc_parse(&a, "") && !fc_parse(&a, "1.2.3"), "bad input rejected");
    CHECK(fc_parse(&a, "2") && fc_to_double(&a) == 2.0, "integer");
    CHECK(fc_parse(&a, "-.5") && fc_to_double(&a) == -0.5, "leading point");

    // Arithmetic against __float128 at 4 limbs (96 fraction bits).
    srand(1);
    for (int i = 0; i < 20000; i++) {
        double x = rnd(), y = rnd() * pow(10, -(rand() % 20));
        fc_from_double(&a, x); fc_from_double(&b, y);
        fc_mul(&c, &a, &b, 4);
        __float128 e = (__float128)x * y;
        CHECK(fabsq(to_q(&c) - e) < 1e-27Q, "mul %g*%g", x, y);
        fc_add(&c, &a, &b, FC_MAX_LIMBS);
        CHECK(fabsq(to_q(&c) - ((__float128)x + y)) < 1e-30Q, "add");
        fc_sub(&c, &a, &b, FC_MAX_LIMBS);
        CHECK(fabsq(to_q(&c) - ((__float128)x - y)) < 1e-30Q, "sub");
    }
    // Tiny offsets survive: the view centre moved by 1e-25 then measured against the start.
    fc_parse(&a, "-1.7490811216528962");
    b = a;
    fc_add_double(&b, 3.25e-25);
    double d = fc_diff_to_double(&b, &a);
    CHECK(fabs(d - 3.25e-25) < 1e-38, "diff %.17g", d);

    // Limb count grows with zoom.
    CHECK(fc_limbs_for_pixel_size(0.004) == 3, "limbs shallow %d", fc_limbs_for_pixel_size(0.004));
    CHECK(fc_limbs_for_pixel_size(1e-33) >= 6, "limbs deep %d", fc_limbs_for_pixel_size(1e-33));

    // Orbits against __float128 iteration, each formula, at a point inside or near the set.
    const char *cr = "-0.10109636384562", *ci = "0.95628651080914";
    for (int f = 0; f < FC_FORMULA_COUNT; f++) {
        fc_num zr, zi, cre, cim;
        fc_zero(&zr); fc_zero(&zi); fc_parse(&cre, cr); fc_parse(&cim, ci);
        static float out[2 * 201];
        int n = fc_orbit(f, &zr, &zi, &cre, &cim, 5, 200, 65536.0, out);
        __float128 x = 0, y = 0, qcr = to_q(&cre), qci = to_q(&cim);
        int bad = 0;
        for (int k = 1; k < n && k < 60; k++) {
            __float128 nx, ny, x2 = x*x, y2 = y*y, xy = x*y;
            switch (f) {
            case FC_BURNING_SHIP: nx = x2 - y2; ny = 2*fabsq(xy); break;
            case FC_TRICORN: nx = x2 - y2; ny = -2*xy; break;
            case FC_MULTIBROT3: nx = x*(x2 - 3*y2); ny = y*(3*x2 - y2); break;
            case FC_CELTIC: nx = fabsq(x2 - y2); ny = 2*xy; break;
            default: nx = x2 - y2; ny = 2*xy; break;
            }
            x = nx + qcr; y = ny + qci;
            if (fabsf(out[2*k] - (float)x) > 1e-5f * (1 + fabsq(x)) || fabsf(out[2*k+1] - (float)y) > 1e-5f * (1 + fabsq(y))) bad++;
        }
        CHECK(bad == 0, "orbit formula %d: %d mismatches (length %d)", f, bad, n);
        CHECK(n >= 2, "orbit length");
    }
    // Escaping orbit stops right after the bailout and stores the escaped point.
    {
        fc_num zr, zi, cre, cim;
        fc_zero(&zr); fc_zero(&zi); fc_from_double(&cre, 1.0); fc_zero(&cim);
        float out[2 * 101];
        int n = fc_orbit(FC_MANDELBROT, &zr, &zi, &cre, &cim, 3, 100, 65536.0, out);
        // 0, 1, 2, 5, 26, 677 (677^2 > 65536)
        CHECK(n == 6 && out[10] == 677.0f, "escape n=%d last=%g", n, out[2*(n-1)]);
    }
    printf(failures ? "%d FAILURES\n" : "all core tests passed\n", failures);
    return failures != 0;
}
