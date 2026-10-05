#include <stdint.h>

// 引入汇编中写好的底层单字节发送函数
extern void asm_uart_putchar(uint8_t ch);

/**
 * 核心补丁：用软件移位减法实现 32 位无符号数除法与取模
 * 完美平替 __divsi3 和 __modsi3，且体积极其轻量
 */
uint32_t sw_div_mod(uint32_t dividend, uint32_t divisor, uint32_t *remainder) {
    uint32_t quotient = 0;
    uint32_t accum = 0;

    // 经典的从高位到低位的恢复余数除法算法
    for (int i = 31; i >= 0; i--) {
        accum = (accum << 1) | ((dividend >> i) & 1);
        if (accum >= divisor) {
            accum -= divisor;
            quotient |= (1U << i);
        }
    }

    // 如果传入了指针，就顺便把余数（取模结果）带回去
    if (remainder) {
        *remainder = accum;
    }
    return quotient; // 返回商（除法结果）
}

/**
 * 1. 打印单个字符 (Char)
 */
void print_char(char c) {
    asm_uart_putchar((uint8_t)c);
}

/**
 * 2. 打印字符串 (String)
 */
void print_str(const char *str) {
    int i = 0;
    while (str[i] != '\0') {
        asm_uart_putchar(str[i]);
        i++;
    }
}

/**
 * 3. 打印有符号32位整型 (Int32)
 * 已用自定义的 sw_div_mod 彻底重构
 */
void print_int(int32_t num) {
    if (num == 0) {
        asm_uart_putchar('0');
        return;
    }

    if (num < 0) {
        asm_uart_putchar('-');
        num = -num; 
    }

    char buffer[12];
    int i = 0;
    uint32_t u_num = (uint32_t)num;

    while (u_num > 0) {
        uint32_t rem;
        // 代替原本的 u_num / 10 和 u_num % 10
        u_num = sw_div_mod(u_num, 10, &rem);
        buffer[i] = rem + '0'; 
        i++;
    }

    while (i > 0) {
        i--;
        asm_uart_putchar(buffer[i]);
    }
}

/**
 * 4. 打印32位十六进制数 (Hex)
 * 十六进制只用移位和位与（>> 和 &），不需要除法，所以天然不会报错
 */
void print_hex(uint32_t num) {
    print_str("0x"); 
    for (int i = 28; i >= 0; i -= 4) {
        uint8_t nibble = (num >> i) & 0x0F;
        if (nibble < 10) {
            asm_uart_putchar(nibble + '0');
        } else {
            asm_uart_putchar(nibble - 10 + 'A');
        }
    }
}

/*
 * Print a small unsigned integer.
 * This is only intended for popcount result 0..32.
 * No division, no modulo, no arrays, no libc.
 *
 * SERV version: use the already-defined SERV output wrapper print_char().
 */
static void serv_put_small_uint(uint32_t x)
{
    if (x >= 30u)
    {
        print_char('3');
        print_char((char)('0' + (x - 30u)));
    }
    else if (x >= 20u)
    {
        print_char('2');
        print_char((char)('0' + (x - 20u)));
    }
    else if (x >= 10u)
    {
        print_char('1');
        print_char((char)('0' + (x - 10u)));
    }
    else
    {
        print_char((char)('0' + x));
    }
}

/*
 * Very simple software popcount.
 * Counts how many bits are 1 in a 32-bit input.
 */
static uint32_t popcount32(uint32_t x)
{
    uint32_t count = 0u;

    for (uint32_t i = 0u; i < 32u; i++)
    {
        count += x & 1u;
        x >>= 1;
    }

    return count;
}

static void run_test(const char *name, uint32_t value)
{
    uint32_t result = popcount32(value);

    print_str(name);
    print_str(" = ");
    serv_put_small_uint(result);
    print_str("\n");
}

int main(void)
{
    print_str("Simple popcount on SERV\n");

    run_test("zero", 0x00000000u);
    run_test("one", 0x00000001u);
    run_test("all_ones", 0xFFFFFFFFu);
    run_test("deadbeef", 0xDEADBEEFu);
    run_test("baadf00d", 0xBAADF00Du);
    run_test("single_msb", 0x80000000u);

    print_str("Done.\n");

    return 0;
}
