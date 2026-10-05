# A minimal standalone SERV firmware — no C, no startup.S needed.
# Prints "S\n" via UART bit-bang, then halts.
# Tests that build.sh can compile a single .S file on its own.

#define GPIO_ADDR 0x40000000
#define HALT_ADDR 0x90000000

.section .text.start
.globl _start
_start:
    # Set up stack pointer (top of 4KB RAM)
    li      sp, 4096

    # GPIO init: set output high
    li      a0, GPIO_ADDR
    addi    t0, zero, 1
    sb      t0, 0(a0)

    # Print character 'S' (0x53) via UART bit-bang
    li      a0, GPIO_ADDR
    li      t0, 0x53            # 'S'

    # Build UART frame: start=0, data=0x53, stop=1
    # Frame bits (LSB first): 0 + 8 data bits + 1 stop = 10 bits
    # Shift data into position, OR with start bit (bit 9 low? no — see below)
    # SERV servant UART protocol: write byte to GPIO, bit-bang via shift
    ori     t0, t0, 0x100       # set bit 9 (stop bit = 1)
    slli    t0, t0, 1           # shift left 1 to make room for start bit

bitbang:
    sb      t0, 0(a0)           # drive UART line
    srli    t0, t0, 1           # shift to next bit
    nop
    nop
    bnez    t0, bitbang         # continue until all bits sent

    # Print newline '\n' (0x0A)
    li      a0, GPIO_ADDR
    li      t0, 0x0A            # '\n'
    ori     t0, t0, 0x100
    slli    t0, t0, 1

bitbang2:
    sb      t0, 0(a0)
    srli    t0, t0, 1
    nop
    nop
    bnez    t0, bitbang2

    # Halt: write to HALT_ADDR to stop simulation
halt:
    li      t0, HALT_ADDR
    sw      zero, 0(t0)
    j       halt
