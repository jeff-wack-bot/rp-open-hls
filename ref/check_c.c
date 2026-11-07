/* Run hls/biquad.c (compiled with gcc) against the Python reference vectors.
 * usage: check_c <1|2> vectors_biquadN.txt */
#include <stdio.h>
#include <stdlib.h>
#include "../hls/biquad.h"

int main(int argc, char **argv)
{
    if (argc < 3) return 2;
    int nsec = atoi(argv[1]);
    FILE *f = fopen(argv[2], "r");
    if (!f) { perror(argv[2]); return 2; }
    unsigned v[13];
    long n = 0, bad = 0;
    int ncol = 3 + 5 * nsec;
    for (;;) {
        int k;
        for (k = 0; k < ncol; k++)
            if (fscanf(f, "%x", &v[k]) != 1) break;
        if (k != ncol) break;
        int32_t *s = (int32_t *)v, y;
        if (nsec == 1)
            y = biquad1(s[1], s[2], s[3], s[4], s[5], s[6], s[0]);
        else
            y = biquad2(s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9],
                        s[10], s[11], s[0]);
        if (y != s[ncol - 1]) {
            if (bad < 10) printf("mismatch at %ld: got %08x want %08x\n", n,
                                 (unsigned)y, v[ncol - 1]);
            bad++;
        }
        n++;
    }
    printf("biquad%d C kernel vs Python reference: %ld vectors, %ld mismatches\n",
           nsec, n, bad);
    return bad != 0 || n == 0;
}
