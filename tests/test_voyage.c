// Tests for the automatic voyage (source/Voyage.c): it is flown here for a minute and a half
// of simulated time over each formula, in double precision, with the engine's depth limit moved
// up to 1e-11 so that the turn round at the bottom is exercised too. Checks that the view
// keeps detail on screen (never lost in the void or in the black), that it keeps diving, and
// that it turns round before the limit. With a folder argument, also writes pictures of the
// journey (PPM) to look at.
//   gcc -O2 -Isource tests/test_voyage.c source/Voyage.c -lm && ./a.out [folder]
#include "FractalCore.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

// Same rule as FractalModel.maxIterations.
static int max_iterations(double half) {
    double octaves = fmax(0, log2(2.5 / half));
    double it = 250 + 90 * octaves;
    return (int)fmin(fmax(it, 64), 200000);
}

static void write_ppm(const char *path, const float *c, int w, int h) {
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) {
        unsigned char rgb[3] = {0, 0, 0};
        if (c[i] >= 0) {
            double t = sqrt(c[i]) * 0.35;
            rgb[0] = (unsigned char)(127.5 + 127.5 * sin(6.2832 * t));
            rgb[1] = (unsigned char)(127.5 + 127.5 * sin(6.2832 * t + 2.1));
            rgb[2] = (unsigned char)(127.5 + 127.5 * sin(6.2832 * t + 4.2));
        }
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
}

typedef struct {
    const char *name;
    int formula, julia;
    double kx, ky, x, y, half;
    double ySign;
} Start;

static void fly(const Start *st, uint32_t seed, const char *outdir) {
    const int W = 80, H = 50;            // probe grid, aspect 1.6 like a window
    const double fps = 30, dt = 1 / fps;
    const double rate = log(2) / 1.2;    // a bit faster than the app's default
    const double minHalf = 1e-11, maxHalf = st->half;
    const double seconds = 100;
    static float probe[80 * 50];
    static float big[320 * 200];

    double cx = st->x, cy = st->y, half = st->half;
    fc_voyage v;
    fc_voyage_start(&v, seed);

    // The app's probe arrives a few frames late; replay that latency.
    double pcx = cx, pcy = cy, phalf = half;
    int pending = 0;
    int looks = 0, lost = 0, turns = 0, worstRun = 0, run = 0;
    double deepest = half, lowestAfterTurn = 0;
    int wasBacking = 0;
    int frames = (int)(seconds * fps);
    for (int f = 0; f < frames; f++) {
        if (f % 6 == 0) {                 // take a probe of the current picture
            fc_preview(st->formula, st->julia, st->kx, st->ky, cx, cy, half, st->ySign, W, H,
                       max_iterations(half), probe);
            pcx = cx; pcy = cy; phalf = half;
            pending = 3;
        }
        if (pending > 0 && --pending == 0) {
            // Offset of the probe's centre from the current one, oriented as on screen.
            double ox = pcx - cx, oy = (pcy - cy) * st->ySign;
            fc_voyage_look(&v, probe, W, H, ox, oy, phalf, half, minHalf, maxHalf);
            looks++;
            // Lost: almost all black, or nothing anywhere worth a look.
            int inside = 0;
            for (int i = 0; i < W * H; i++) inside += probe[i] < 0;
            int isLost = inside > 0.92 * W * H || v.lastScore < 0.06;
            lost += isLost;
            run = isLost ? run + 1 : 0;
            if (run > worstRun) worstRun = run;
            if (v.backing == 2 && !wasBacking) turns++;
            wasBacking = v.backing == 2;
            if (outdir && looks % 25 == 0) {
                char path[512];
                snprintf(path, sizeof path, "%s/voyage-%s-%u-%03d.ppm", outdir, st->name, seed, looks / 25);
                fc_preview(st->formula, st->julia, st->kx, st->ky, cx, cy, half, st->ySign, 320, 200,
                           max_iterations(half), big);
                write_ppm(path, big, 320, 200);
            }
        }
        double mx, my;
        double z = fc_voyage_step(&v, dt, rate, half, &mx, &my);
        cx += mx;
        cy += my * st->ySign;
        half *= z;
        if (half < deepest) deepest = half;
        if (turns > 0 && v.backing == 0 && half > lowestAfterTurn) lowestAfterTurn = half;
    }
    printf("%-14s seed %u: %4d looks, lost %4.1f%% (longest %d), deepest %.1e, turned round %d times\n",
           st->name, seed, looks, 100.0 * lost / looks, worstRun, deepest, turns);
    CHECK(lost <= looks / 20, "%s: lost in %d of %d looks", st->name, lost, looks);
    CHECK(worstRun <= 12, "%s: lost for %d looks in a row", st->name, worstRun);
    CHECK(deepest >= minHalf, "%s: went below the deepest zoom (%.2e)", st->name, deepest);
    CHECK(turns >= 1, "%s: never reached the bottom (deepest %.2e)", st->name, deepest);
}

int main(int argc, char **argv) {
    const char *outdir = argc > 1 ? argv[1] : NULL;

    // Cell scores: black, flat and noise are dull; a boundary is interesting.
    {
        enum { N = 16 };
        float s[N * N];
        for (int i = 0; i < N * N; i++) s[i] = -1;
        CHECK(fc_voyage_cell_score(s, N, N, 0, 0, N, N) == 0, "black cell");
        for (int i = 0; i < N * N; i++) s[i] = 5.0f + (i % N) * 0.01f;
        CHECK(fc_voyage_cell_score(s, N, N, 0, 0, N, N) < 0.06, "flat cell %g", fc_voyage_cell_score(s, N, N, 0, 0, N, N));
        srand(3);
        for (int i = 0; i < N * N; i++) s[i] = (float)(exp(6.0 * rand() / RAND_MAX));
        double noise = fc_voyage_cell_score(s, N, N, 0, 0, N, N);
        // A real boundary: the Mandelbrot set near the seahorse valley.
        fc_preview(FC_MANDELBROT, 0, 0, 0, -0.7453, 0.1127, 0.0065, 1, N, N, 1000, s);
        double edge = fc_voyage_cell_score(s, N, N, 0, 0, N, N);
        CHECK(edge > 2 * noise && edge > 0.1, "boundary %g vs noise %g", edge, noise);
        printf("cell scores: boundary %.2f, noise %.2f\n", edge, noise);
    }

    const Start starts[] = {
        {"mandelbrot", FC_MANDELBROT, 0, 0, 0, -0.6, 0, 1.25, 1},
        {"burning-ship", FC_BURNING_SHIP, 0, 0, 0, -0.45, -0.5, 1.2, -1},
        {"tricorn", FC_TRICORN, 0, 0, 0, -0.3, 0, 1.4, 1},
        {"multibrot3", FC_MULTIBROT3, 0, 0, 0, 0, 0, 1.3, 1},
        {"celtic", FC_CELTIC, 0, 0, 0, -0.5, 0, 1.4, 1},
        {"julia-rabbit", FC_MANDELBROT, 1, -0.123, 0.745, 0, 0, 1.3, 1},
        {"julia-spirals", FC_MANDELBROT, 1, -0.7269, 0.1889, 0, 0, 1.2, 1},
    };
    for (unsigned i = 0; i < sizeof starts / sizeof *starts; i++)
        fly(&starts[i], 7919 + i, outdir);

    printf(failures ? "%d FAILURES\n" : "all voyage tests passed\n", failures);
    return failures != 0;
}
