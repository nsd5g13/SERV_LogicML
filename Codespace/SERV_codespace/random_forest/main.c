#include <stdint.h>
#include "RF_model.h"
#include "samples.h"
#include "infer_one.h"

#define DEBUG_MAILBOX (*(volatile uint32_t *)0x40101200)

// ----------------------------------------------
int result_array[no_samples];

int main()
{
    for (int i = 0; i < no_samples; i++)
    {
        result_array[i] = infer_one(raw_samples[i]);
    }

    // For debugging only
    for (int i = 0; i < no_samples; i++) {
        DEBUG_MAILBOX = (uint32_t)result_array[i];
    }

    return 0;
}

