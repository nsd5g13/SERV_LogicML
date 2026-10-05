//#include "datapoint.h"

#include "TA_actions_uint32.h"
#include "samples_tm.h"

/*
 * Computes the output of every clause (0 or 1) and packs them into bits
 * of a 32-bit word, so that class_sum.c can count the 1s with the
 * (custom) popcount instruction.
 *
 * Clause i (0 .. CLASSES*CLAUSES-1) is stored in bit i of the packed
 * array: bit = 1  → clause output 1,  bit = 0  → clause output 0.
 *
 * CLASSES*CLAUSES = 3*10 = 30, so all clauses fit into one 32-bit word.
 */
void compute_clause_output(const unsigned int Xi[], unsigned int packed_clause_output[]) {
    int LITERALS = RAW_FEATURES * no_bits * 2;
    int NUM_GROUPS = (LITERALS + 31) / 32;  
    int NUM_WORDS = (CLASSES * CLAUSES + 31) / 32;

    /* Clear the packed array (we only OR set bits in below). */
    for (int w = 0; w < NUM_WORDS; w++)
        packed_clause_output[w] = 0;

    for (int i = 0; i < CLAUSES*CLASSES; i++) {
        int c_out = 1;
	unsigned int inter_combined = 0xFFFFFFFF;

	if (NUM_GROUPS == 1) {
	    unsigned int ta = ta_actions[i][0];
	    unsigned int y = Xi[0] | ~ta;
	    if (y != 0xFFFFFFFF){
	        c_out = 0;
	    }
	}
	else {
	    for (int j = 0; j < NUM_GROUPS; j++) {
	        unsigned int ta = ta_actions[i][j];
		unsigned int y_group = Xi[j] | ~ta;
		inter_combined &= y_group;
		if (inter_combined != 0xFFFFFFFF){
		    c_out = 0;
		    break;
		}
	    }
	}

        /* Pack this clause's output as one bit. */
        if (c_out) {
            int w = i >> 5;
            int b = i & 31;
            packed_clause_output[w] |= (1u << b);
        }
    }

}
