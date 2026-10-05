/*
 * range_popcount_v2_cyc.c — cycle-cost baseline for v2 RTL (e81a9cf)
 *
 * v2 semantics: rs2 carries the ABSOLUTE END ADDRESS, not a byte offset.
 * Same 10-word array as the v3 cycle test; rs2 = start + 36 so both measure
 * the same closed-interval [start, start+36] = 10 word reads.
 *
 * No UART output (would perturb cycle cost). startup.S halts via 0x90000000.
 *
 * Build & run:
 *   ./build.sh --folder=cycle_cost_test_v2 --build
 *   (RTL must be at e81a9cf, e.g. git stash in the serv submodule)
 *   ./run_sim.sh --build --run
 *   grep popcount in log/compare_result.txt
 */

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
    unsigned int start = (unsigned int)&test_data[0];
    unsigned int end   = start + 36; /* absolute end address (v2 semantics) */

    /* popcount rd, rs1(start), rs2(end_addr): funct7=0000000 rs2 rs1 funct3=000 rd 0101011 */
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, %2"
                 : "=r"(rd) : "r"(start), "r"(end));

    (void)rd;
    return 0;
}
