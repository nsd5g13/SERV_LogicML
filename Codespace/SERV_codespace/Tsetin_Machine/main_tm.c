#include "TA_actions_uint32.h"
#include "samples_tm.h"

//#define RESULT_ARRAY_ADDR 0x00002000

extern void booleanization(const int raw_samples[], unsigned int bool_literals[]);
extern void compute_clause_output(const unsigned int bool_literals[], unsigned int packed_clause_output[]);
extern int compute_class_sum(const unsigned int packed_clause_output[]);

int result_array[no_samples];

/* Bit-packed boolean literals (2*no_bits*RAW_FEATURES bits, MSB-first). */
unsigned int bool_literals[(2*no_bits*RAW_FEATURES+31)/32];
//volatile int* bool_literals = (int*) RESULT_ARRAY_ADDR;

/* Bit-packed clause outputs (1 bit per clause) — counted via popcount in
 * compute_class_sum() instead of a plain loop. */
unsigned int clause_output[(CLASSES*CLAUSES+31)/32];
//volatile int* result_array = (int*) RESULT_ARRAY_ADDR;

int main() {
    
    for (int i = 0; i < no_samples; i++) {
	//int bool_literals[no_bits*RAW_FEATURES];
	booleanization(raw_samples[i], bool_literals);

        //int clause_output[CLASSES*CLAUSES];
        compute_clause_output(bool_literals, clause_output);
        
	/* Display clause output */
        /*printf("Clause outputs for sample %d: ", i);
        for (int j = 0; j < CLAUSES*CLASSES; j++) {
            printf("%d ", clause_output[j]);
        }
        printf("\n");*/
        
	/* Display predicted class */
        result_array[i] = compute_class_sum(clause_output);
	//*tohost = result_array[i];
	/*printf("Predicted class: %d\n", result);*/
    }

    return 0;
    //while(1);
}
