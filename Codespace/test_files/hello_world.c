#include <stdint.h>

/*
 * Ibex Simple System memory-mapped peripherals.
 *
 * ASCII output:
 *   Write one byte/word here, simulator records it into ibex_simple_system.log
 *
 * Simulation halt:
 *   Write 1 here to request simulator termination.
 */
#define IBEX_SIM_PRINT_ADDR 0x00020000u
#define IBEX_SIM_HALT_ADDR  0x00020008u

static void ibex_putchar(char c)
{
    volatile uint32_t *print_reg = (volatile uint32_t *)IBEX_SIM_PRINT_ADDR;
    *print_reg = (uint32_t)c;
}

static void ibex_puts(const char *s)
{
    while (*s) {
        ibex_putchar(*s);
        s++;
    }
}

static void ibex_halt(void)
{
    volatile uint32_t *halt_reg = (volatile uint32_t *)IBEX_SIM_HALT_ADDR;
    *halt_reg = 1u;

    /*
     * If the simulator does not halt immediately for any reason,
     * stay here instead of falling through.
     */
    while (1) {
    }
}

int main(void)
{
    ibex_puts("Hello world from Codespace on Ibex!\n");
    ibex_puts("This is my own C program, not the official hello_test.\n");
    ibex_puts("Ibex Verilator simulation is working.\n");

    ibex_halt();

    return 0;
}
