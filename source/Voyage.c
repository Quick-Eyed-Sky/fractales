// Fractales -- previews and the automatic voyage. See FractalCore.h.
//
// The voyage zooms in without end and steers by itself. Several times a second it looks at a
// small grid of escape counts sampled from the picture on screen, cuts it into square cells and
// scores each cell: how much the counts vary across it (structure), how much they vary from one
// sample to the next (fine detail), minus what looks like noise (neighbours differing as much as
// the whole cell: chaos), and nothing for cells that are mostly inside the set (black) or flat
// (empty). It heads for the best cell near the middle and stays on it unless a clearly better one
// shows up, so the camera glides instead of jumping. When everything in view is dull it backs out
// until detail comes back; near the deepest zoom the engine allows, it turns round, climbs back
// up a long way and dives again somewhere else.

#include "FractalCore.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// ---- Previews: escape counts computed directly in double precision ----

static void escape_step(int formula, double *x, double *y, double cx, double cy) {
    double X = *x, Y = *y, x2 = X * X, y2 = Y * Y, nx, ny;
    switch (formula) {
    case FC_BURNING_SHIP: nx = x2 - y2; ny = 2 * fabs(X * Y); break;
    case FC_TRICORN: nx = x2 - y2; ny = -2 * X * Y; break;
    case FC_MULTIBROT3: nx = X * (x2 - 3 * y2); ny = Y * (3 * x2 - y2); break;
    case FC_CELTIC: nx = fabs(x2 - y2); ny = 2 * X * Y; break;
    default: nx = x2 - y2; ny = 2 * X * Y; break;
    }
    *x = nx + cx;
    *y = ny + cy;
}

void fc_preview(int formula, int julia, double kx, double ky, double cx, double cy,
                double halfHeight, double ySign, int w, int h, int maxIter, float *out) {
    const double bailout2 = 65536.0;  // same as the GPU, so the colours match
    double logPower = log(formula == FC_MULTIBROT3 ? 3.0 : 2.0);
    double pixel = 2 * halfHeight / h;
    for (int j = 0; j < h; j++) {
        double py = cy + (0.5 * h - (j + 0.5)) * pixel * ySign;
        for (int i = 0; i < w; i++) {
            double px = cx + (i + 0.5 - 0.5 * w) * pixel;
            double x = julia ? px : 0, y = julia ? py : 0;
            double ccx = julia ? kx : px, ccy = julia ? ky : py;
            float result = -1.0f;
            for (int n = 0; n < maxIter; n++) {
                escape_step(formula, &x, &y, ccx, ccy);
                double r2 = x * x + y * y;
                if (r2 > bailout2) {
                    double s = n + 1 - log(0.5 * log(r2)) / logPower;
                    result = (float)(s > 0 ? s : 0);
                    break;
                }
            }
            out[j * w + i] = result;
        }
    }
}

// ---- Voyage ----

#define CELL_MIN 4
#define DEAD_SCORE 0.06       // below this everywhere, the view is empty: back out
#define ALIVE_SCORE 0.15      // backing out from a dead end stops once a cell is this good

static double rand01(fc_voyage *v) {
    // xorshift32: the voyage only needs variety, and the same seed replays the same voyage.
    uint32_t s = v->seed ? v->seed : 0x9E3779B9u;
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
    v->seed = s;
    return (s >> 8) * (1.0 / 16777216.0);
}

void fc_voyage_start(fc_voyage *v, uint32_t seed) {
    memset(v, 0, sizeof *v);
    v->seed = seed ? seed : 1;
    v->fresh = 1;
}

#define ROUGH 0.3            // change between neighbouring samples (log of the count) that reads as grain

// True if the escaping sample (i, j) differs from an escaping neighbour by more than ROUGH.
static int rough_at(const float *s, int w, int h, int i, int j) {
    double l = log1p(s[j * w + i]);
    const int di[4] = {1, -1, 0, 0}, dj[4] = {0, 0, 1, -1};
    for (int k = 0; k < 4; k++) {
        int x = i + di[k], y = j + dj[k];
        if (x < 0 || y < 0 || x >= w || y >= h || s[y * w + x] < 0) continue;
        if (fabs(log1p(s[y * w + x]) - l) > ROUGH) return 1;
    }
    return 0;
}

double fc_voyage_cell_score(const float *s, int w, int h, int x0, int y0, int cw, int ch) {
    int n = 0, escaped = 0, pairs = 0, rough = 0;
    double sum = 0, sum2 = 0, diff = 0;
    for (int j = y0; j < y0 + ch && j < h; j++) {
        for (int i = x0; i < x0 + cw && i < w; i++) {
            float c = s[j * w + i];
            n++;
            if (c < 0) continue;
            escaped++;
            double l = log1p(c);
            sum += l;
            sum2 += l * l;
            rough += rough_at(s, w, h, i, j);
            if (i + 1 < x0 + cw && i + 1 < w && s[j * w + i + 1] >= 0) {
                diff += fabs(log1p(s[j * w + i + 1]) - l);
                pairs++;
            }
            if (j + 1 < y0 + ch && j + 1 < h && s[(j + 1) * w + i] >= 0) {
                diff += fabs(log1p(s[(j + 1) * w + i]) - l);
                pairs++;
            }
        }
    }
    if (n == 0 || escaped < 3 || pairs == 0) return 0;
    double inside = 1.0 - (double)escaped / n;
    if (inside > 0.7) return 0;                   // mostly black: a dead end
    double mean = sum / escaped;
    double sigma = sqrt(fmax(sum2 / escaped - mean * mean, 0));
    double g = diff / pairs;                      // typical change from one sample to the next
    double structure = fmin(sigma, 1.2);
    double fine = fmin(g, 0.6);
    double score = sqrt(structure * fine);
    // Noise: neighbours as different as the whole cell (white noise gives about 1.13).
    double r = g / (sigma + 0.02);
    double excess = fmax(0, r - 0.6);
    score /= 1 + 12 * excess * excess;
    // Chaos: grain all over the cell. Some grain is the edge of the detail; a cell full of it
    // is a sea of dust where no shape ever comes out.
    double q = (double)rough / escaped;
    if (q > 0.3) score *= fmax(0, (0.8 - q) / 0.5);
    // A little of the set in view (a miniature copy, a bay) is what makes a zoom beautiful.
    if (inside > 0.02 && inside < 0.4) score *= 1.2;
    if (inside > 0.5) score *= (0.7 - inside) / 0.2;
    return score;
}

void fc_voyage_look(fc_voyage *v, const float *s, int w, int h,
                    double ox, double oy, double probeHalf,
                    double halfHeight, double minHalf, double maxHalf) {
    if (w < CELL_MIN || h < CELL_MIN) return;
    int cell = h / 8 > CELL_MIN ? h / 8 : CELL_MIN;
    int nx = w / cell, ny = h / cell;
    if (nx < 1 || ny < 1) return;
    int x0 = (w - nx * cell) / 2, y0 = (h - ny * cell) / 2;
    double spacing = 2 * probeHalf / h;           // complex units between two samples

    // Too deep for the engine: turn round and climb back up a long way.
    if (!v->backing && halfHeight < minHalf * 64) {
        v->backing = 2;
        double octaves = 14 + 18 * rand01(v);
        v->backUntil = fmin(halfHeight * pow(2, octaves), maxHalf);
    }

    double best = -1, bestRaw = 0, bestX = 0, bestY = 0;
    double current = -1;   // weighted score of the cell holding the current target
    for (int cj = 0; cj < ny; cj++) {
        for (int ci = 0; ci < nx; ci++) {
            int sx = x0 + ci * cell, sy = y0 + cj * cell;
            double raw = fc_voyage_cell_score(s, w, h, sx, sy, cell, cell);
            if (raw > bestRaw) bestRaw = raw;
            if (raw <= 0) continue;
            // Aim at the escaping sample with the highest count among those that are not grain:
            // the closest to the set where shapes are still clear, so the zoom follows the
            // boundary instead of drifting into the smooth outside or into the dust.
            int bi = sx + cell / 2, bj = sy + cell / 2;
            float bc = -2;
            for (int j = sy; j < sy + cell; j++)
                for (int i = sx; i < sx + cell; i++)
                    if (s[j * w + i] > bc && !rough_at(s, w, h, i, j)) { bc = s[j * w + i]; bi = i; bj = j; }
            double px = ox + (bi + 0.5 - 0.5 * w) * spacing;
            double py = oy + (0.5 * h - (bj + 0.5)) * spacing;
            double weight;
            if (v->fresh) {
                weight = 0.3 + 0.7 * rand01(v);   // a new start: any good cell may win
            } else {
                double d2 = (px * px + py * py) / (halfHeight * halfHeight);
                weight = 0.35 + 0.65 * exp(-d2 / 0.5);
            }
            double score = raw * weight;
            if (score > best) { best = score; bestX = px; bestY = py; }
            // The cell the current target lies in.
            if (v->hasTarget) {
                double cx0 = ox + (sx - 0.5 * w) * spacing, cx1 = cx0 + cell * spacing;
                double cy1 = oy + (0.5 * h - sy) * spacing, cy0 = cy1 - cell * spacing;
                if (v->targetX >= cx0 && v->targetX < cx1 && v->targetY >= cy0 && v->targetY < cy1)
                    current = score;
            }
        }
    }
    v->lastScore = bestRaw;

    if (v->backing == 2) return;   // keep climbing; a new dive starts once high enough (fc_voyage_step)
    if (bestRaw < DEAD_SCORE) {
        if (!v->backing) {   // nothing worth seeing: back out a few octaves and look again
            v->backing = 1;
            v->backUntil = fmin(halfHeight * 8, maxHalf);
        }
        return;
    }
    if (v->backing == 1 && bestRaw >= ALIVE_SCORE) {
        v->backing = 0;
        v->fresh = 1;
    }
    if (v->backing) return;

    // Keep the current target unless a clearly better one appears: no jitter.
    if (!v->hasTarget || v->fresh || current < 0 || best > 1.3 * current) {
        v->targetX = bestX;
        v->targetY = bestY;
        v->hasTarget = 1;
    }
    v->fresh = 0;
}

double fc_voyage_step(fc_voyage *v, double dt, double rate, double halfHeight,
                      double *moveX, double *moveY) {
    *moveX = 0;
    *moveY = 0;
    if (dt <= 0) return 1;
    if (dt > 0.1) dt = 0.1;   // after a stall, carry on smoothly rather than leap
    double zoomRate;
    if (v->backing) {
        zoomRate = -(v->backing == 2 ? 3.0 : 1.5) * rate - 0.3;   // out, faster than in
        if (halfHeight * exp(-zoomRate * dt) >= v->backUntil) {
            v->backing = 0;
            v->fresh = 1;
            v->hasTarget = 0;
        }
    } else if (!v->hasTarget) {
        zoomRate = 0;         // waiting for the first look
    } else {
        // Slow down while the target is far from the middle, so the zoom never overtakes it.
        double d = sqrt(v->targetX * v->targetX + v->targetY * v->targetY) / halfHeight;
        double slow = 1.4 - d;
        if (slow > 1) slow = 1;
        if (slow < 0.1) slow = 0.1;
        zoomRate = rate * slow;
    }
    if (v->hasTarget) {
        double k = 1.6 + 2 * fabs(rate);
        double f = 1 - exp(-k * dt);
        *moveX = v->targetX * f;
        *moveY = v->targetY * f;
        v->targetX -= *moveX;
        v->targetY -= *moveY;
    }
    return exp(-zoomRate * dt);
}
