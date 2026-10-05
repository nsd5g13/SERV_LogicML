#include "infer_one.h"

// Custom popcount instruction: rd = number of set bits in val
volatile static unsigned int popcnt_custom(unsigned int val)
{
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0"
                 : "=r"(rd) : "r"(val));
    return rd;
}

// Returns prediction for one datapoint
int infer_one(const int *x)
{
    // Each tre e's class vote (0..CLASSES-1) is packed into a 2-bit field
    // of a 32-bit word. CLASSES=3 -> 2 bits/vote; TREES=10 -> 20 bits, fits.
    unsigned int packed_votes = 0;
    int vote_count = 0;

    int row = 0;

    while (trees[row][0] != 0 || trees[row][1] != 0 ||
           trees[row][2] != 0 || trees[row][3] != 0)
    {
        int feature = trees[row][0];
        int value   = trees[row][1];

        // leaf?
        if (value == -1)
        {
            int cls = (int)feature;
            packed_votes |= (unsigned int)cls << (2 * vote_count);
            vote_count++;

            // skip to next tree
            while (!(trees[row][0] == 0 && trees[row][1] == 0 &&
                     trees[row][2] == 0 && trees[row][3] == 0))
                row++;

            // skip the {0,0,0,0}
            row++;
            continue;
        }

        int fidx = (int)feature;
        int split = value;
        int left  = (int)trees[row][2];
        int right = (int)trees[row][3];

        if (x[fidx] < split)
            row = left + row;
        else
            row = right + row;
    }

    // Majority vote using the custom popcount instruction.
    // In each 2-bit field: 00 = class 0, 01 = class 1, 10 = class 2.
    unsigned int lo = packed_votes & 0x55555555;         // low bit of each field
    unsigned int hi = (packed_votes >> 1) & 0x55555555;  // high bit of each field

    // count1 = fields equal to 01, count2 = fields equal to 10
    unsigned int count1 = popcnt_custom(lo & ~hi);
    unsigned int count2 = popcnt_custom(hi & ~lo);
    unsigned int count0 = (unsigned int)vote_count - count1 - count2;

    int best_class = 0, best_count = (int)count0;
    if ((int)count1 > best_count) { best_class = 1; best_count = (int)count1; }
    if ((int)count2 > best_count) { best_class = 2; best_count = (int)count2; }

    return best_class;
}
