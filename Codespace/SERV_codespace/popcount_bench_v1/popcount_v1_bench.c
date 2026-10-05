/*
 * popcount_v1_bench.c
 *
 * Benchmark round 2: CUSTOM INSTRUCTION V1 (32-bit register popcount).
 * popcount rd, rs1  — counts 1-bits in the rs1 REGISTER.
 *
 * Requires the Phase-1 RTL (submodule commit ac5aa03).
 * Computes the total popcount of a 5-word array by calling the custom
 * instruction once per element (with loads + loop overhead), stores the
 * result, then halts.
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

/* V1 register popcount: popcount rd, rs1  (rs2 = x0) */
static unsigned int popcount_v1(unsigned int val) {
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0"
                 : "=r"(rd) : "r"(val));
    return rd;
}

static unsigned int popcount_all(void) {
    unsigned int total = 0;
    for (int i = 0; i < 5; i++) {
        total += popcount_v1(arr[i]);
    }
    return total;
}

int main(void) {
    unsigned int total = popcount_all();
    *(volatile unsigned char *)0x80000000 = (unsigned char)total;  // low byte = 0x58 for 88
    *(volatile unsigned int *)0x90000000 = 0;
    return 0;
}
