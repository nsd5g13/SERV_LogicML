#include "samples_tm.h"

void selectionSort(int arr[], int n) {
	for (int i = 0; i < n - 1; i++) {
		int min = i;
		for (int j = i + 1; j < n; j++) {
			if (arr[j] < arr[min])
				min = j;
		}
		if (min != i) {
			int temp = arr[min];
			arr[min] = arr[i];
			arr[i] = temp;
		}
	}
}

void booleanization(const int Xi[], unsigned int bool_literals[]) {
	
    int total_bits = RAW_FEATURES * no_bits;
    int total_bits_doubled = total_bits * 2;  // originals + complements
    int num_ints = (total_bits_doubled + 31) / 32;

    // Initialize packed array
    for (int i = 0; i < num_ints; i++)
        bool_literals[i] = 0;

    int bit_index = 0;
    int complement_start = total_bits;

    for (int i = 0; i < RAW_FEATURES; i++) {
        int feature_thresholds[no_bits];

        // Copy thresholds
        for (int j = 0; j < no_bits - 1; j++)
            feature_thresholds[j] = thresholds[i][j];

        int raw_feature = Xi[i];
        feature_thresholds[no_bits - 1] = raw_feature;

        selectionSort(feature_thresholds, no_bits); // must be ascending

        int idx = 0;
        for (int j = 0; j < no_bits; j++) {
            if (feature_thresholds[j] == raw_feature) {
                idx = j;
                break;
            }
        }

        // Write all original bits first, then complements
        for (int j = 0; j < no_bits; j++) {
            int bit_val = (j == idx) ? 1 : 0;

            // --- Write ORIGINAL (MSB-first) ---
            int word_index = bit_index / 32;
            int bit_offset = bit_index % 32;
            if (bit_val)
                bool_literals[word_index] |= (1u << (31 - bit_offset));

            // --- Write COMPLEMENT (MSB-first) ---
            int comp_index = complement_start + bit_index;
            int comp_word = comp_index / 32;
            int comp_offset = comp_index % 32;
            if (!bit_val)
                bool_literals[comp_word] |= (1u << (31 - comp_offset));

            bit_index++;
        }
    }
}
