#include <stdint.h>
#include <stddef.h>
//#include <stdio.h>
#include "layer0.h"
#include "layer1_uint32.h"
#include "samples_bnn.h"
#include "helpers.h"

// --- main function ---
int32_t result_array[no_samples];

int main(void) {
    // Forward pass
    int32_t yout1[no_samples][NEURONS0];
    dense0(raw_samples, LAYER0, yout1, NEURONS0, ACTIVATIONS0, 1); // first layer: use_ste_sign=1
    uint32_t yout1_packed[no_samples][ACTIVATIONS1_PACKED];
    pack_bits(yout1, yout1_packed, no_samples);
    int32_t yout2[no_samples][NEURONS1];
    dense1(yout1_packed, LAYER1, yout2, NEURONS1, ACTIVATIONS1_PACKED, 0, NEURONS0); // second layer: no activation

    argmax(yout2, result_array, no_samples, NEURONS1);

    // For debugging only
    //for (int i = 0; i < no_samples; i++) {
    //    printf("%d ", result_array[i]);
    //}
    //printf("\n");

    // labels now contain the predicted class for each sample
    //while(1); // bare-metal infinite loop
    return 0;
}
