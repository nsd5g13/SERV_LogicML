#include <stdint.h>

// this is R type customized instruction
int customized_cube(int addr){

    int cube;
    asm volatile(".insn r 0x7b, 6, 6, %0, %1, x0": "=r"(cube)
                                                 : "r"(addr));

    return cube;
}

int main(void){
    int addr = 10;
    
    return customized_cube(addr);
}