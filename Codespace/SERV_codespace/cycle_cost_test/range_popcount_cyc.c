/*
 * range_popcount_cyc.c — cycle-cost measurement for the custom popcount
 *
 * Runs the custom instruction ONCE over a 10-word array (same array size as
 * the v2 regression test, offset = 36 -> closed interval [start, start+36])
 * with no UART output, then returns. startup.S halts the simulation by
 * writing to 0x90000000.
 *
 * Purpose: read the custom instruction's cycle cost from
 *     log/sim_log.txt / log/compare_result.txt
 * and compare it between v2 and v3 RTL. Nothing is printed on purpose, so
 * the reported cost is not perturbed by UART activity.
 *
 * Build & run:
 *   ./build.sh --folder=cycle_cost_test --build
 *   ./run_sim.sh --build --run            (or ./run_sim.sh --run if built)
 *   grep popcount in log/compare_result.txt
 */

/* Same 10-word data array as the v2 regression test */
static unsigned int test_data[10] = {
    0x00000000,
    0xFFFFFFFF,
    0xDEADBEEF,
    0x55555555,
    0xAAAAAAAA,
    0x0F0F0F0F,
    0xF0F0F0F0,
    0x12345678,
    0x89ABCDEF,
    0x00000001
};

int main(void) {
    unsigned int rd;
    unsigned int start  = (unsigned int)&test_data[0];
    unsigned int offset = 36; /* 10 words -> (offset>>2)+1 = 10 reads */

    /* popcount rd, rs1(start), rs2(offset): funct7=0000000 rs2 rs1 funct3=000 rd 0101011 */
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, %2"
                 : "=r"(rd) : "r"(start), "r"(offset));

    (void)rd; /* result unused here; asm volatile keeps the instruction */
    return 0;
}
