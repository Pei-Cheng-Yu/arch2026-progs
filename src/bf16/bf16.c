#include "bf16.h"
#define F32_EXP_MASK 0x7F800000u

#define BF16_NAN 0x7FC0u
#define BF16_INF 0x7F80u
#define BF16_INF_NEG 0xFF80u
#define BF16_ONE 0x3F80u

#define BF16_SIGN_MASK 0x8000u
#define BF16_EXP_MASK 0x7F80u
#define BF16_MANT_MASK 0x007Fu
#define BF16_HIDDEN_BIT 0x0080u
#define BF16_MAG_MASK 0x7FFFu
#define BF16_EXP_BIAS 127
/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits & F32_EXP_MASK) == F32_EXP_MASK)
        return (uint16_t) (f32bits >> 16);
    uint32_t last_kept_bit = (f32bits >> 16) & 1u;
    f32bits += 0x7FFFu + last_kept_bit;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & BF16_SIGN_MASK;

    int32_t exp_a = (a >> 7) & 0xFFu;
    int32_t exp_b = (b >> 7) & 0xFFu;

    uint32_t mant_a = a & BF16_MANT_MASK;
    uint32_t mant_b = b & BF16_MANT_MASK;

    if (exp_a == 0xFF) {
        if (mant_a != 0)
            return a;
        if ((b & BF16_MAG_MASK) == 0)
            return BF16_NAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if (exp_b == 0xFF) {
        if (mant_b != 0)
            return b;

        if ((a & BF16_MAG_MASK) == 0)
            return BF16_NAN;

        return (uint16_t) (sign | BF16_INF);
    }
    if ((a & BF16_MAG_MASK) == 0 || (b & BF16_MAG_MASK) == 0)
        return (uint16_t) sign;

    /* Normalize a. */
    if (exp_a == 0) {
        exp_a = 1;

        while (mant_a < BF16_HIDDEN_BIT) {
            mant_a <<= 1;
            exp_a--;
        }
    } else {
        mant_a |= BF16_HIDDEN_BIT;
    }

    /* Normalize b. */
    if (exp_b == 0) {
        exp_b = 1;

        while (mant_b < BF16_HIDDEN_BIT) {
            mant_b <<= 1;
            exp_b--;
        }
    } else {
        mant_b |= BF16_HIDDEN_BIT;
    }
    uint32_t product = mant_a * mant_b;
    int32_t result_exp = exp_a + exp_b - BF16_EXP_BIAS;
    if (product >= 0x8000u) {
        product >>= 1;
        result_exp++;
    }
    uint32_t result_mant = (product >> 7) & BF16_MANT_MASK;
    /* Overflow: return signed infinity. */
    if (result_exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);

    /* Underflow: return a subnormal or signed zero. */
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) sign;

        result_mant >>= 1 - result_exp;
        return (uint16_t) (sign | result_mant);
    }

    /* Normal result: remove the hidden bit and pack the fields. */
    return (uint16_t) (sign | ((uint32_t) result_exp << 7) |
                       (result_mant & BF16_MANT_MASK));
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
