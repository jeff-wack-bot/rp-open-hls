/* HLS kernel source: compiled unchanged by gcc (C reference) and by Bambu. */
#include "biquad.h"

/* Sum of three Q4.28 x Q16.16 products, wrap mod 2^64, return bits [59:28].
 * Unsigned arithmetic makes the wrap well defined in C; the final
 * conversion to int32 keeps the low 32 bits (two's complement). */
static inline int32_t mac3(int32_t a, int32_t x, int32_t b, int32_t y,
                           int32_t c, int32_t z)
{
    uint64_t s = (uint64_t)((int64_t)a * x) + (uint64_t)((int64_t)b * y) +
                 (uint64_t)((int64_t)c * z);
    return (int32_t)(uint32_t)(s >> BQ_COEF_FRAC);
}

int32_t biquad1(int32_t x, int32_t g, int32_t c0, int32_t c1, int32_t a10,
                int32_t a11, int32_t clear)
{
    static int32_t w = 0, u = 0;
    if (clear) {
        w = 0;
        u = 0;
    }
    int32_t y = mac3(g, x, c0, w, c1, u);
    int32_t wn = mac3(g, x, a10, w, a11, u);
    u = (int32_t)((uint32_t)u + (uint32_t)w);
    w = wn;
    return y;
}

int32_t biquad2(int32_t x,
                int32_t g0, int32_t c00, int32_t c01, int32_t a010, int32_t a011,
                int32_t g1, int32_t c10, int32_t c11, int32_t a110, int32_t a111,
                int32_t clear)
{
    static int32_t w0 = 0, u0 = 0, w1 = 0, u1 = 0;
    if (clear) {
        w0 = 0; u0 = 0; w1 = 0; u1 = 0;
    }
    int32_t t = mac3(g0, x, c00, w0, c01, u0);
    int32_t wn0 = mac3(g0, x, a010, w0, a011, u0);
    u0 = (int32_t)((uint32_t)u0 + (uint32_t)w0);
    w0 = wn0;
    int32_t y = mac3(g1, t, c10, w1, c11, u1);
    int32_t wn1 = mac3(g1, t, a110, w1, a111, u1);
    u1 = (int32_t)((uint32_t)u1 + (uint32_t)w1);
    w1 = wn1;
    return y;
}
