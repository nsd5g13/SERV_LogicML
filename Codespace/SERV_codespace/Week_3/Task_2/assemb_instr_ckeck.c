#include <stdint.h>

int main(void){
    int A = 10;
    const int B = 1;

    if (A != B){
        return B;
    }

    return A;
}