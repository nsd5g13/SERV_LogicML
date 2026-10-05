// popcount.c — Cycle-cost benchmark using rdcycle
// Measures the cycle cost of the popcount function on PicoRV32.
// Compiled with startup_pico.S (provides _start → main).

#include <stdint.h>

// Volatile sinks to prevent -O2 from deleting the computation
volatile uint32_t popcount_result;
volatile uint32_t cycle_count;

__attribute__((noinline, used)) uint32_t popcount(uint32_t in_reg){
    uint32_t count = 0;

    for(int i = 0; i < 32; i++){
        uint32_t temp = (in_reg >> i) & 1;
        if(temp == 1) {
            count = count + 1;
        }
    }

    return count;
}

int main(void){
    uint32_t reg_x1 = 19149;
    uint32_t start, end;

    // Read cycle counter before popcount
    __asm__ volatile ("rdcycle %0": "=r"(start));

    popcount_result = popcount(reg_x1);

    // Read cycle counter after popcount
    __asm__ volatile ("rdcycle %0": "=r"(end));

    // Store the cycle cost
    cycle_count = end - start;

    return (int)popcount_result;
}
