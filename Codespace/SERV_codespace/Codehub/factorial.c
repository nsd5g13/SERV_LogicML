#include <stdint.h>

extern void asm_uart_putchar(uint8_t ch);

void print_str(const char *s) {
    while (*s) asm_uart_putchar(*s++);
}

/* Software division — RV32I has no hardware div */
static uint32_t div10(uint32_t n) {
    uint32_t q = 0, acc = 0;
    for (int i = 31; i >= 0; i--) {
        acc = (acc << 1) | ((n >> i) & 1);
        if (acc >= 10) { acc -= 10; q |= (1U << i); }
    }
    return q;
}

static uint32_t mod10(uint32_t n) {
    /* n - div10(n)*10, but avoid hardware mul: x*10 = (x<<3)+(x<<1) */
    uint32_t d = div10(n);
    uint32_t d10 = (d << 3) + (d << 1);
    return n - d10;
}

void print_uint(uint32_t n) {
    if (n == 0) { asm_uart_putchar('0'); return; }
    char buf[12];
    int i = 0;
    while (n > 0) { buf[i++] = '0' + mod10(n); n = div10(n); }
    while (i > 0) asm_uart_putchar(buf[--i]);
}

/* Multiply via shift-and-add — compiler won't optimize this away */
static uint32_t soft_mul(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    while (b > 0) {
        if (b & 1) r += a;
        a <<= 1;
        b >>= 1;
    }
    return r;
}

/* Factorial: using soft_mul to avoid __mulsi3 */
static uint32_t fact(uint32_t n) {
    uint32_t result = 1;
    for (uint32_t i = 2; i <= n; i++)
        result = soft_mul(result, i);
    return result;
}

int main(void) {
    print_str("factorial:\n");
    for (uint32_t n = 1; n <= 10; n++) {
        print_str("  ");
        print_uint(n);
        print_str("! = ");
        print_uint(fact(n));
        asm_uart_putchar('\n');
    }
    print_str("done\n");
    return 0;
}
