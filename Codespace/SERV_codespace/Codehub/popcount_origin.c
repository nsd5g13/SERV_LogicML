#include <stdint.h>

volatile uint32_t popcount_sink;

__attribute__((noinline, used)) uint32_t popcount(uint32_t in_reg){
    uint32_t count1 = 0;

    for(int i = 0; i < 32; i++){
        if(((in_reg >> i) & 1) == 1) {
            count1 = count1 + 1;
        }
    }

    return count1;
}

int main(void){
    uint32_t reg_x1 = 19149;

    popcount_sink = popcount(reg_x1);

    return popcount_sink; 
}
