/*
 * LIGO-form biquad section, fixed point, plain C99 (no ap_fixed, no pragmas),
 * so that open HLS front ends (Bambu) and gcc both accept it unchanged.
 *
 *   tmp = G*x + C0*w + C1*u
 *   w'  = G*x + A10*w + A11*u
 *   u'  = u + w            (old w)
 *   y   = tmp
 *
 * Number formats (match hls_codegen.py defaults: signal ap_fixed<32,16>,
 * coef ap_fixed<32,4>, AP_TRN, AP_WRAP):
 *   signals  x, y, w, u : int32, Q16.16  (an ADC code k enters as k << 16 or as
 *                                         a raw integer, the scaling is the
 *                                         caller's choice; the filter is linear)
 *   coefs    G,C0,C1,A10,A11 : int32, Q4.28
 *   products            : exact 64 bit (Q20.44)
 *   sum of 3 products   : 64 bit, wraps modulo 2^64
 *   result              : bits [59:28] of the sum (truncate toward -inf, then
 *                         wrap to 32 bits) == ap_fixed AP_TRN/AP_WRAP
 */
#ifndef BIQUAD_H
#define BIQUAD_H
#include <stdint.h>

#define BQ_COEF_FRAC 28

typedef struct {
    int32_t g, c0, c1, a10, a11;
} bq_coef_t;

/* One section, state in static variables (registers in hardware). */
int32_t biquad1(int32_t x, int32_t g, int32_t c0, int32_t c1, int32_t a10,
                int32_t a11, int32_t clear);

/* Two cascaded sections. */
int32_t biquad2(int32_t x,
                int32_t g0, int32_t c00, int32_t c01, int32_t a010, int32_t a011,
                int32_t g1, int32_t c10, int32_t c11, int32_t a110, int32_t a111,
                int32_t clear);

#endif
