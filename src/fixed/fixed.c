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
    uint64_t product = 0;
    uint64_t shifted = ua;

    while (ub != 0) {
        if (ub & 1u)
            product += shifted;

        shifted <<= 1;
        ub >>= 1;
    }
    int64_t signed_product = (int64_t) product;

    if ((a < 0) != (b < 0))
        signed_product = -signed_product;
    signed_product += INT64_C(1) << 19;
    signed_product >>= 20;
    return (int32_t) signed_product;
}
