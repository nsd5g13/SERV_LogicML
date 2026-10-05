#include <stdint.h>

extern void asm_uart_putchar(unsigned int c);

volatile uint32_t popcount_sink;

static void putstr(const char *s) {
    while (*s)
        asm_uart_putchar((unsigned int)*s++);
}

static void puthex(uint32_t v) {
    int i;
    for (i = 7; i >= 0; i--) {
        uint32_t nib = (v >> (i * 4)) & 0xF;
        asm_uart_putchar(nib < 10 ? ('0' + nib) : ('A' + nib - 10));
    }
}

/* Official Zbb cpop, enabled for this asm block only.
 *
 * -march stays rv32i globally, so GCC's instruction selection can never emit
 * any other Zb* instruction (clz/ctz/min/max/rol/andn/orn/xnor/rev8), none of
 * which this RTL implements.  `.option` is an *assembler* directive: it lets
 * `as` accept the cpop mnemonic here, and GAS tags exactly this region with a
 * `$xrv32i2p1_zbb1p0` mapping symbol, so objdump decodes it back as `cpop`
 * instead of a bare `.insn`.
 *
 * Do NOT put zbb into -march: that hands the whole extension to the compiler,
 * and e.g. `lo & ~hi` becomes andn -- which SERV silently evaluates as a plain
 * and (measured on random_forest: every sample misclassified as class 0).
 *
 * Was: __builtin_popcount() under `build.sh --zbb`, with a volatile input to
 * defeat constant folding.  Both are now unnecessary -- inline asm is opaque
 * to the optimiser, so a literal input can no longer fold the popcount away. */
volatile static unsigned int popcnt_custom(unsigned int val) {
    unsigned int rd;
    asm volatile(".option push\n"
                 ".option arch, +zbb\n"
                 "cpop %0, %1\n"
                 ".option pop\n"
                 : "=r"(rd) : "r"(val));
    return rd;
}

int main(void){
    uint32_t reg_x1 = 0x000fffff;

    popcount_sink = popcnt_custom(reg_x1);

    putstr("popcount_sink = 0x");
    puthex(popcount_sink);
    putstr("\n");

    *(volatile unsigned int *)0x90000000 = 0;
    return popcount_sink;
}
