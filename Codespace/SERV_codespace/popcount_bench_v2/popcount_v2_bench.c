/*
 * popcount_v2_bench.c
 *
 * Benchmark round 3: CUSTOM INSTRUCTION V2 (memory-range popcount).
 * popcount rd, rs1(start_addr), rs2(end_addr) — counts 1-bits over the
 * inclusive word-aligned memory range [start, end].
 *
 * Requires the Phase-2 RTL (submodule commit e81a9cf, current HEAD).
 * Computes the total popcount of a 5-word array with ONE range call,
 * stores the result, then halts.
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

/* V2 range popcount: popcount rd, rs1(start), rs2(end) */
static unsigned int popcount_v2(unsigned int start, unsigned int end) {
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, %2"
                 : "=r"(rd) : "r"(start), "r"(end));
    return rd;
}

static unsigned int popcount_all(void) {
    return popcount_v2((unsigned int)&arr[0], (unsigned int)&arr[4]);
}

int main(void) {
    unsigned int total = popcount_all();
    *(volatile unsigned char *)0x80000000 = (unsigned char)total;  // low byte = 0x58 for 88
    *(volatile unsigned int *)0x90000000 = 0;
    return 0;
}
