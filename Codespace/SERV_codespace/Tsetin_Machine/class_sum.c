#include <limits.h>  // for INT_MIN
#include "samples_tm.h"
#include "TA_actions_uint32.h"

/*
 * Portable population count.
 *
 *  - Modified SERV (built with -DUSE_CUSTOM_POPCOUNT):
 *      uses the hardware popcount instruction
 *      (.insn r 0x2B, 0, 0 — custom encoding implemented in the
 *       customized SERV ALU).
 *  - Original SERV (default build, no flag):
 *      software popcount fallback that runs on any RISC-V core.
 *
 * This is the "bit-packing + popcount" trick used in the random-forest
 * implementation: clause outputs are packed into 32-bit words
 * (1 bit per clause) and counted with popcount instead of a loop.
 */
static inline unsigned int popcnt(unsigned int val)
{
#ifdef USE_CUSTOM_POPCOUNT
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0"
                 : "=r"(rd) : "r"(val));
    return rd;
#else
    unsigned int n = 0;
    while (val) {
        val &= val - 1;   /* clear the lowest set bit */
        n++;
    }
    return n;
#endif
}

/* All clause bits must fit into one 32-bit word for the packing scheme
 * below (CLASSES*CLAUSES = 3*10 = 30 <= 32). */
#if (CLASSES * CLAUSES > 32)
#error "compute_class_sum packing assumes CLASSES*CLAUSES <= 32"
#endif

int compute_class_sum(const unsigned int packed_clause_output[]) {
    int max_score = INT_MIN;
    int best_class = -1;

    /* Clause i is packed in bit i (see clause_output.c). */
    unsigned int packed = packed_clause_output[0];

    for (int c = 0; c < CLASSES; c++) {
        int base = c * CLAUSES;
        int half = CLAUSES / 2;

        /* Positive clauses: [base, base+half)            → add */
        /* Negative clauses: [base+half, base+CLAUSES)    → subtract */
        unsigned int pos_mask = ((1u << half) - 1u) << base;
        unsigned int neg_mask = ((1u << half) - 1u) << (base + half);

        int sum = (int)popcnt(packed & pos_mask) - (int)popcnt(packed & neg_mask);

        if (sum > max_score) {
            max_score = sum;
            best_class = c;
        }
    }

    return best_class;
}

