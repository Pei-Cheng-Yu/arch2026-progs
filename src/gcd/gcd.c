#include "gcd.h"

/* Dummy: returns 0 for every input. Replace with the binary GCD. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned shift = 0;

    while (a != b) {
        if ((a & 1u) == 0 && (b & 1u) == 0) {
            a >>= 1;
            b >>= 1;
            shift++;
        } else if ((a & 1u) == 0) {
            a >>= 1;
        } else if ((b & 1u) == 0) {
            b >>= 1;
        } else if (a > b) {
            a -= b;
        } else {
            b -= a;
        }
    }

    return a << shift;
}
