// Fractales -- high-precision core. See FractalCore.h.

#include "FractalCore.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#define TOP (FC_MAX_LIMBS - 1)

static int is_neg(const fc_num *a) { return (a->d[TOP] >> 31) != 0; }

static int clamp_limbs(int nl) {
    if (nl < 2) return 2;
    if (nl > FC_MAX_LIMBS) return FC_MAX_LIMBS;
    return nl;
}

int fc_limbs_for_pixel_size(double pixelSize) {
    if (!(pixelSize > 0)) return FC_MAX_LIMBS;
    double bits = -log2(pixelSize) + 32.0;
    int frac = (int)ceil(bits / 32.0);
    if (frac < 1) frac = 1;
    return clamp_limbs(frac + 1);
}

void fc_zero(fc_num *a) { memset(a, 0, sizeof *a); }

void fc_neg(fc_num *out, const fc_num *a, int nl) {
    nl = clamp_limbs(nl);
    int base = FC_MAX_LIMBS - nl;
    uint64_t carry = 1;
    for (int i = base; i < FC_MAX_LIMBS; i++) {
        uint64_t v = (uint64_t)(uint32_t)~a->d[i] + carry;
        out->d[i] = (uint32_t)v;
        carry = v >> 32;
    }
    for (int i = 0; i < base; i++) out->d[i] = 0;
}

void fc_abs(fc_num *out, const fc_num *a, int nl) {
    if (is_neg(a)) {
        fc_neg(out, a, nl);
    } else {
        nl = clamp_limbs(nl);
        int base = FC_MAX_LIMBS - nl;
        for (int i = base; i < FC_MAX_LIMBS; i++) out->d[i] = a->d[i];
        for (int i = 0; i < base; i++) out->d[i] = 0;
    }
}

void fc_add(fc_num *out, const fc_num *a, const fc_num *b, int nl) {
    nl = clamp_limbs(nl);
    int base = FC_MAX_LIMBS - nl;
    uint64_t carry = 0;
    for (int i = base; i < FC_MAX_LIMBS; i++) {
        uint64_t v = (uint64_t)a->d[i] + b->d[i] + carry;
        out->d[i] = (uint32_t)v;
        carry = v >> 32;
    }
    for (int i = 0; i < base; i++) out->d[i] = 0;
}

void fc_sub(fc_num *out, const fc_num *a, const fc_num *b, int nl) {
    nl = clamp_limbs(nl);
    int base = FC_MAX_LIMBS - nl;
    uint64_t borrow = 0;
    for (int i = base; i < FC_MAX_LIMBS; i++) {
        uint64_t v = (uint64_t)a->d[i] - b->d[i] - borrow;
        out->d[i] = (uint32_t)v;
        borrow = (v >> 32) & 1;
    }
    for (int i = 0; i < base; i++) out->d[i] = 0;
}

void fc_mul(fc_num *out, const fc_num *a, const fc_num *b, int nl) {
    nl = clamp_limbs(nl);
    int base = FC_MAX_LIMBS - nl;
    int neg = is_neg(a) ^ is_neg(b);
    fc_num A, B;
    fc_abs(&A, a, nl);
    fc_abs(&B, b, nl);
    const uint32_t *x = &A.d[base], *y = &B.d[base];

    uint32_t prod[2 * FC_MAX_LIMBS] = {0};
    for (int i = 0; i < nl; i++) {
        uint64_t carry = 0;
        uint64_t xi = x[i];
        if (xi == 0) continue;
        for (int j = 0; j < nl; j++) {
            uint64_t t = xi * y[j] + prod[i + j] + carry;
            prod[i + j] = (uint32_t)t;
            carry = t >> 32;
        }
        prod[i + nl] = (uint32_t)carry;
    }
    // Both factors carry (nl - 1) fraction limbs, the product 2(nl - 1): drop the lowest nl - 1.
    for (int k = 0; k < nl; k++) out->d[base + k] = prod[nl - 1 + k];
    for (int i = 0; i < base; i++) out->d[i] = 0;
    if (neg) fc_neg(out, out, nl);
}

void fc_from_double(fc_num *out, double x) {
    fc_zero(out);
    int neg = x < 0;
    double m = fabs(x);
    if (!(m < 2147483647.0)) m = 2147483647.0; // also catches NaN
    double ip = floor(m);
    out->d[TOP] = (uint32_t)ip;
    double f = m - ip;
    for (int i = TOP - 1; i >= 0 && f != 0; i--) {
        f *= 4294967296.0;
        double l = floor(f);
        out->d[i] = (uint32_t)l;
        f -= l;
    }
    if (neg) fc_neg(out, out, FC_MAX_LIMBS);
}

double fc_to_double(const fc_num *a) {
    fc_num m;
    int neg = is_neg(a);
    fc_abs(&m, a, FC_MAX_LIMBS);
    int k = TOP;
    while (k >= 0 && m.d[k] == 0) k--;
    if (k < 0) return 0.0;
    double v = 0.0;
    for (int i = k; i >= 0 && i > k - 3; i--)
        v += ldexp((double)m.d[i], 32 * (i - TOP));
    return neg ? -v : v;
}

void fc_add_double(fc_num *a, double x) {
    fc_num t;
    fc_from_double(&t, x);
    fc_add(a, a, &t, FC_MAX_LIMBS);
}

double fc_diff_to_double(const fc_num *a, const fc_num *b) {
    fc_num t;
    fc_sub(&t, a, b, FC_MAX_LIMBS);
    return fc_to_double(&t);
}

static void div_small(fc_num *a, uint32_t q) { // a >= 0
    uint64_t rem = 0;
    for (int i = TOP; i >= 0; i--) {
        uint64_t cur = (rem << 32) | a->d[i];
        a->d[i] = (uint32_t)(cur / q);
        rem = cur % q;
    }
}

int fc_parse(fc_num *out, const char *s) {
    fc_zero(out);
    while (*s == ' ' || *s == '\t') s++;
    int neg = 0;
    if (*s == '-') { neg = 1; s++; } else if (*s == '+') { s++; }
    uint64_t ip = 0;
    int any = 0;
    while (*s >= '0' && *s <= '9') {
        ip = ip * 10 + (uint64_t)(*s - '0');
        if (ip > 2147483647u) return 0;
        s++; any = 1;
    }
    const char *frac = NULL, *fracEnd = NULL;
    if (*s == '.') {
        s++;
        frac = s;
        while (*s >= '0' && *s <= '9') { s++; any = 1; }
        fracEnd = s;
    }
    while (*s == ' ' || *s == '\t' || *s == '\n') s++;
    if (*s != 0 || !any) return 0;

    // Fraction: from the last digit to the first, f = (digit + f) / 10.
    fc_num f;
    fc_zero(&f);
    if (frac) {
        for (const char *p = fracEnd; p > frac; p--) {
            f.d[TOP] += (uint32_t)(p[-1] - '0');
            div_small(&f, 10);
        }
    }
    f.d[TOP] = (uint32_t)ip;
    *out = f;
    if (neg) fc_neg(out, out, FC_MAX_LIMBS);
    return 1;
}

int fc_to_string(const fc_num *a, int digits, char *buf, size_t bufSize) {
    if (bufSize == 0) return 0;
    fc_num m;
    int neg = is_neg(a);
    fc_abs(&m, a, FC_MAX_LIMBS);
    char tmp[64];
    size_t n = 0;
    int len = snprintf(tmp, sizeof tmp, "%s%u", neg ? "-" : "", m.d[TOP]);
    for (int i = 0; i < len && n + 1 < bufSize; i++) buf[n++] = tmp[i];
    if (digits > 0 && n + 1 < bufSize) buf[n++] = '.';
    for (int k = 0; k < digits && n + 1 < bufSize; k++) {
        m.d[TOP] = 0;
        uint64_t carry = 0;
        for (int i = 0; i <= TOP; i++) {
            uint64_t v = (uint64_t)m.d[i] * 10 + carry;
            m.d[i] = (uint32_t)v;
            carry = v >> 32;
        }
        buf[n++] = (char)('0' + m.d[TOP]);
    }
    buf[n] = 0;
    return (int)n;
}

int fc_orbit(int formula, const fc_num *z0re, const fc_num *z0im,
             const fc_num *cre, const fc_num *cim,
             int nl, int maxIter, double bailout2, float *out) {
    nl = clamp_limbs(nl);
    if (maxIter < 1) maxIter = 1;
    fc_num x = *z0re, y = *z0im;
    fc_num x2, y2, xy, t, u;

    double xd = fc_to_double(&x), yd = fc_to_double(&y);
    out[0] = (float)xd;
    out[1] = (float)yd;
    int count = 1;
    double r2 = xd * xd + yd * yd;
    if (r2 > 1e8) { // too large to square in fixed point; the pixel escapes at once anyway
        out[2] = out[0];
        out[3] = out[1];
        return 2;
    }

    while (count < maxIter + 1) {
        if (count >= 2 && r2 > bailout2) break;
        fc_mul(&x2, &x, &x, nl);
        fc_mul(&y2, &y, &y, nl);
        fc_mul(&xy, &x, &y, nl);
        switch (formula) {
        case FC_BURNING_SHIP:
            fc_sub(&t, &x2, &y2, nl);
            fc_abs(&xy, &xy, nl);
            fc_add(&u, &xy, &xy, nl);
            break;
        case FC_TRICORN:
            fc_sub(&t, &x2, &y2, nl);
            fc_add(&u, &xy, &xy, nl);
            fc_neg(&u, &u, nl);
            break;
        case FC_MULTIBROT3: {
            fc_num three;
            fc_add(&three, &y2, &y2, nl);
            fc_add(&three, &three, &y2, nl);  // 3y^2
            fc_sub(&t, &x2, &three, nl);       // x^2 - 3y^2
            fc_mul(&t, &t, &x, nl);            // x^3 - 3xy^2
            fc_add(&three, &x2, &x2, nl);
            fc_add(&three, &three, &x2, nl);  // 3x^2
            fc_sub(&u, &three, &y2, nl);       // 3x^2 - y^2
            fc_mul(&u, &u, &y, nl);            // 3x^2y - y^3
            break;
        }
        case FC_CELTIC:
            fc_sub(&t, &x2, &y2, nl);
            fc_abs(&t, &t, nl);
            fc_add(&u, &xy, &xy, nl);
            break;
        default: // FC_MANDELBROT
            fc_sub(&t, &x2, &y2, nl);
            fc_add(&u, &xy, &xy, nl);
            break;
        }
        fc_add(&x, &t, cre, nl);
        fc_add(&y, &u, cim, nl);

        xd = fc_to_double(&x);
        yd = fc_to_double(&y);
        out[2 * count] = (float)xd;
        out[2 * count + 1] = (float)yd;
        count++;
        r2 = xd * xd + yd * yd;
    }
    return count;
}
