#include <stdint.h>

/*#define putchar(ch) (*(volatile uint32_t *)0x10000000 = (ch))

uint32_t start, end;

static void print_str(const char *s) {
    while (*s) putchar(*s++);
}

static uint32_t div10(uint32_t n) {
    uint32_t q = 0, acc = 0;
    for (int i = 31; i >= 0; i--) {
        acc = (acc << 1) | ((n >> i) & 1);
        if (acc >= 10) { acc -= 10; q |= (1U << i); }
    }
    return q;
}

static void print_uint(uint32_t n) {
    if (n == 0) { putchar('0'); return; }
    char buf[12];
    int i = 0;
    while (n > 0) { buf[i++] = '0' + (n - div10(n)*10); n = div10(n); }
    while (i > 0) putchar(buf[--i]);
}*/

__attribute__((noinline, used)) int popcount(uint32_t x) {

    //__asm__ volatile ("rdcycle %0" : "=r"(start));

    int count = 0;
    while (x != 0) {
        if (x & 1) count++;
        x >>= 1;
    }

    //__asm__ volatile ("rdcycle %0" : "=r"(end));

    return count;
}

int main(void) {
    volatile uint32_t val = 0b10110101;

    volatile int result = popcount(val);


    /*
    print_str("Popcount benchmark\n");
    print_str("Input:  10110101\n");
    print_str("Result: ");
    print_uint(result);
    putchar('\n');
    print_str("Cycles: ");
    print_uint(end - start);
    putchar('\n');
    print_str("Instructions approx: ");
    print_uint((end - start));
    putchar('\n');
    if (result == 5) print_str("PASS\n");
    else print_str("FAIL\n");*/

    return 0;
}
