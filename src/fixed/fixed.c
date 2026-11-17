#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;

    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a = a ^ b;
        b = carry;
        (*n)++;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;

    if (a < 0)
        ua = 0u - ua;

    if (b < 0)
        ub = 0u - ub;
    uint32_t product_lo = 0, product_hi = 0;
    uint32_t shifted_lo = ua, shifted_hi = 0;

    while (ub != 0) {
        if (ub & 1u) {
            uint32_t old_lo = product_lo;
            product_lo += shifted_lo;
            product_hi += shifted_hi + (product_lo < old_lo);
        }
        shifted_hi = (shifted_hi << 1) | (shifted_lo >> 31);
        shifted_lo <<= 1;
        ub >>= 1;
    }

    if ((a < 0) != (b < 0)) {
        product_hi = ~product_hi + (product_lo == 0);
        product_lo = 0u - product_lo;
    }
    uint32_t old_lo = product_lo;
    product_lo += UINT32_C(1) << 19;
    product_hi += product_lo < old_lo;
    return (int32_t) ((product_hi << 12) | (product_lo >> 20));
}
