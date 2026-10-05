#include <zephyr/sys/printk.h>  
#include <stdint.h>

void popcount(uint32_t in_reg){
    uint32_t count0 = 0;
    uint32_t count1 = 0;

    for(int i = 0; i < 32; i++){
        uint32_t temp = in_reg >> i;
        temp = temp & 1;
        if(temp == 1) {
            count1 = count1 + 1;
        } else {
            count0 = count0 + 1;
        }
    }

    printk("1 numbers: %d; 0 numbers: %d\n", count1, count0);
}

int main(void){
    uint32_t reg_x1 = 19149;

    popcount(reg_x1);

    return 0;
}
