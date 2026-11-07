/* Multi-rate experiment: the rate change is written in C. One call pops
 * DECIM ADC samples from a FIFO-mode port (125 MS/s side), averages them,
 * and runs the 2-section cascade once (125/DECIM MS/s side).
 * Bambu: --generate-interface=INFER makes `adc` a FIFO read port
 * (adc_dout / adc_empty_n / adc_read), the rest stays MINIMAL. */
#include "biquad.h"
#define DECIM 16

#pragma HLS interface port = adc mode = fifo
int32_t decim_biquad2(volatile int16_t *adc,  /* volatile: else LLVM hoists the 16 reads into one pop */
                      int32_t g0, int32_t c00, int32_t c01, int32_t a010, int32_t a011,
                      int32_t g1, int32_t c10, int32_t c11, int32_t a110, int32_t a111,
                      int32_t clear)
{
    int32_t acc = 0;
    for (int i = 0; i < DECIM; i++)
        acc += *adc;                       /* one FIFO pop per iteration */
    int32_t x = (int32_t)((uint32_t)acc << 12); /* mean in Q16.16 (16 = 2^4) */
    return biquad2(x, g0, c00, c01, a010, a011, g1, c10, c11, a110, a111, clear);
}
