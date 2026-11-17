#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exponent = (f32bits >> 23) & 0xFFu;
    if (exponent == 0xFFu)
        return (uint16_t) (f32bits >> 16);
    uint32_t last_kept_bit = (f32bits >> 16) & 1u;
    f32bits += 0x7FFFu + last_kept_bit;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    (void) a;
    (void) b;
    return 0;
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
