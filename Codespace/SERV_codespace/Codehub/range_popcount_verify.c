/*
 * range_popcount_verify.c
 *
 * Test for the custom memory-range popcount instruction (v2):
 *     popcount rd, rs1(start_addr), rs2(byte_offset)
 *
 * v2 semantics: rs2 carries a byte OFFSET (0..2048), not an absolute end
 * address. The hardware counts 1-bits over the closed interval
 * [start, start+offset] at 4-byte word granularity, i.e.
 *     nwords = (offset >> 2) + 1  words (offset floor to 4).
 * Non-4-byte-aligned start addresses are truncated to the containing word
 * by the memory (the FSM steps by +4 from the given start).
 *
 * Each boundary case compares the custom-instruction result against a
 * software reference; the final result is reported via UART and a
 * signature write (0x80000000 = 'P'/'F').
 *
 * Build: ./build.sh --build --run
 * Expected: RESULT: PASS, all boundary cases PASS.
 */

extern void asm_uart_putchar(unsigned char ch);

static void print_str(const char *s) {
    while (*s) asm_uart_putchar((unsigned char)*s++);
}

static void print_hex(unsigned int val) {
    for (int i = 7; i >= 0; i--) {
        unsigned int nibble = (val >> (i * 4)) & 0xF;
        if (nibble < 10)
            asm_uart_putchar('0' + nibble);
        else
            asm_uart_putchar('a' + nibble - 10);
    }
}

/* Division-free decimal printer (RV32I has no hardware divide) */
static void print_uint(unsigned int val) {
    char buf[12];
    int pos = 11;
    buf[11] = '\0';
    do {
        unsigned int r = val;
        unsigned int q = 0;
        while (r >= 10) { r -= 10; q++; }
        buf[--pos] = '0' + r;
        val = q;
    } while (val);
    print_str(&buf[pos]);
}

/*
 * Custom instruction: popcount rd, rs1(start_addr), rs2(byte_offset)
 *   opcode = 0x2B (custom-0), funct3 = 000, funct7 = 000
 *   Encoding: funct7=0000000 rs2 rs1 funct3=000 rd 0101011
 *   v2: only rs2[11:0] is captured (byte offset, 0..2048).
 */
static unsigned int popcnt_range_custom(unsigned int start, unsigned int offset) {
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, %2"
                 : "=r"(rd) : "r"(start), "r"(offset));
    return rd;
}

/*
 * Software popcount over n consecutive words starting at the given
 * (word-aligned) address. Uses only standard RV32I instructions.
 */
static unsigned int popcnt_sw_n(unsigned int addr_aligned, unsigned int nwords) {
    unsigned int count = 0;
    for (unsigned int w = 0; w < nwords; w++) {
        unsigned int word = *(volatile unsigned int *)(addr_aligned + 4 * w);
        for (int i = 0; i < 32; i++) {
            if ((word >> i) & 1)
                count++;
        }
    }
    return count;
}

/*
 * Reference for a (possibly misaligned) start + byte offset: the hardware
 * reads floor(offset/4)+1 words, each address truncating to the containing
 * word, so the effective word range starts at start & ~3.
 */
static unsigned int popcnt_range_sw(unsigned int start, unsigned int offset) {
    return popcnt_sw_n(start & ~3u, (offset >> 2) + 1);
}

/* Run one boundary case; prints PASS/FAIL, returns 1 on pass */
static int check_case(const char *name, unsigned int start, unsigned int offset,
                      unsigned int expected) {
    unsigned int custom = popcnt_range_custom(start, offset);
    int ok = (custom == expected);
    print_str("  ");
    print_str(name);
    print_str(": custom=");
    print_uint(custom);
    print_str(" expect=");
    print_uint(expected);
    print_str(ok ? "  PASS\n" : "  FAIL\n");
    return ok;
}

/* 10 test words (word-aligned by the compiler) */
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
    unsigned int start = (unsigned int)&test_data[0];
    int all_pass = 1;

    /* ---- main test: 10 words = offset 36 ---- */
    unsigned int custom_res = popcnt_range_custom(start, 36);
    unsigned int sw_res     = popcnt_range_sw(start, 36);

    print_str("range: 0x");
    print_hex(start);
    print_str(" offset=36 (10 words)\n");

    print_str("custom = ");
    print_uint(custom_res);
    print_str(" (0x");
    print_hex(custom_res);
    print_str(")\n");

    print_str("sw     = ");
    print_uint(sw_res);
    print_str(" (0x");
    print_hex(sw_res);
    print_str(")\n");

    if (custom_res != sw_res) all_pass = 0;

    /* ---- boundary cases ---- */
    print_str("boundary cases:\n");
    if (!check_case("offset 0      ", start, 0, popcnt_range_sw(start, 0)))
        all_pass = 0;
    if (!check_case("offset 4      ", start, 4, popcnt_range_sw(start, 4)))
        all_pass = 0;
    if (!check_case("offset 8      ", start, 8, popcnt_range_sw(start, 8)))
        all_pass = 0;
    if (!check_case("offset 7 (unal)", start, 7, popcnt_range_sw(start, 7)))
        all_pass = 0;
    /* misaligned start: addr+2 truncates to test_data[0], 3 words total */
    if (!check_case("start+2 off 8 ", start + 2, 8, popcnt_range_sw(start + 2, 8)))
        all_pass = 0;

    /* ---- max offset 2048: 513 all-ones words -> 513*32 = 16416 ---- */
    {
        static unsigned int big_data[513];
        for (unsigned int i = 0; i < 513; i++)
            big_data[i] = 0xFFFFFFFFu;
        if (!check_case("offset 2048 (max)",
                        (unsigned int)&big_data[0], 2048, 16416))
            all_pass = 0;
    }

    if (all_pass)
        print_str("RESULT: PASS\n");
    else
        print_str("RESULT: FAIL\n");

    /* Signature-based result (for automated check):
     *   0x80000000 <- 'P' if pass, 'F' if fail
     *   0x80000004 <- main-test custom result (low byte)
     */
    *(volatile unsigned char *)0x80000000 = all_pass ? 'P' : 'F';
    *(volatile unsigned char *)0x80000004 = (unsigned char)custom_res;

    *(volatile unsigned int *)0x90000000 = 0;
    return 0;
}
