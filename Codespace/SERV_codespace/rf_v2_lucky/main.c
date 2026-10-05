#include <stdint.h>
#include "RF_model.h"
#include "samples.h"
#include "infer_one.h"

// ----------------------------------------------
int result_array[no_samples];

int main()
{
    for (int i = 0; i < no_samples; i++)
    {
        result_array[i] = infer_one(raw_samples[i]);
    }

    return 0;
}

