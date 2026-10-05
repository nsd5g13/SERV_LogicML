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

static unsigned int popcnt_custom(unsigned int val) {
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0"
                 : "=r"(rd) : "r"(val));
    return rd;
}

static unsigned int popcnt_sw(unsigned int val) {
    unsigned int count = 0;
    unsigned int tmp = val;
    for (int i = 0; i < 32; i++) {
        if (tmp & 1)
            count++;
        tmp >>= 1;
    }
    return count;
}

#ifndef MAX_TEST
#define MAX_TEST 10000
#endif

int main(void) {
    unsigned int failed = 0;
    unsigned int total = 0;

    for (unsigned int val = 0; val < MAX_TEST; val += 10) {
        unsigned int cr = popcnt_custom(val);
        unsigned int sr = popcnt_sw(val);
        total++;

        if (cr == sr) {
            print_str("P ");
        } else {
            print_str("F ");
            failed++;
        }
        print_str("0x"); print_hex(val);
        print_str(" c=0x"); print_hex(cr);
        print_str(" s=0x"); print_hex(sr);
        print_str("\n");
    }

    print_str("\n=== SUMMARY ===\n");
    print_str("Total: "); print_uint(total); print_str("\n");
    print_str("Pass:  "); print_uint(total - failed); print_str("\n");
    print_str("Fail:  "); print_uint(failed); print_str("\n");

    if (failed) {
        print_str("FAIL details above (lines prefixed with F)\n");
    } else {
        print_str("ALL PASSED\n");
    }

    *(volatile unsigned int *)0x90000000 = 0;
    return 0;
}
