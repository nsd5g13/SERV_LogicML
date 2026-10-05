/*
 * popcount_sw_bench.c
 *
 * Benchmark round 1: SOFTWARE popcount (original algorithm).
 * Computes the total popcount of a 5-word array using a standard
 * RV32I bit loop, stores the result, then halts.
 *
 * Expected total = 0+32+24+16+16 = 88 = 0x58
 */

static unsigned int arr[5] = {
    0x00000000,
    0xFFFFFFFF,
    0xDEADBEEF,
    0x55555555,
    0xAAAAAAAA
};

static unsigned int popcount_sw(unsigned int val) {
    unsigned int count = 0;
    unsigned int tmp = val;
    for (int i = 0; i < 32; i++) {
        if (tmp & 1)
            count++;
        tmp >>= 1;
    }
    return count;
}

static unsigned int popcount_all(void) {
    unsigned int total = 0;
    for (int i = 0; i < 5; i++) {
        total += popcount_sw(arr[i]);
    }
    return total;
}

int main(void) {
    unsigned int total = popcount_all();
    *(volatile unsigned char *)0x80000000 = (unsigned char)total;  // low byte = 0x58 for 88
    *(volatile unsigned int *)0x90000000 = 0;
    return 0;
}
