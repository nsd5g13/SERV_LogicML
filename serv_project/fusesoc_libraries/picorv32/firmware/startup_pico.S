// ═══════════════════════════════════════════════════════════════════════
//  PicoRV32 Startup Code
// ═══════════════════════════════════════════════════════════════════════
//
//  Responsibilities:
//    1. Initializes stack pointer `sp` to top of 128KB RAM (0x00020000).
//    2. Calls C program entry point `main()`.
//    3. Halts execution by triggering `ebreak` (raises `trap` signal,
//       which the Verilator testbench detects to report total cycle count).
//    4. Provides `asm_uart_putchar` compatible with SERV benchmarks,
//       mapping character output to PicoRV32 MMIO UART address 0x10000000.
//
// ═══════════════════════════════════════════════════════════════════════

.section .text
.global _start

_start:
    // Initialize stack pointer to top of 128KB RAM (0x00020000)
    lui  sp, %hi(0x00020000)
    addi sp, sp, %lo(0x00020000)

    // Zero-initialize BSS section
    la   t0, _sbss
    la   t1, _ebss
    bgeu t0, t1, 2f
1:
    sw   zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:

    // Call main()
    jal  ra, main

    // Signal success to testbench (write 123456789 to 0x20000000)
    li   t0, 0x20000000
    li   t1, 123456789
    sw   t1, 0(t0)

    // Halt: execute ebreak to trigger trap signal and stop simulation
    ebreak

    // Loop indefinitely as safety net
    j    .

// ── MMIO UART Output Function ────────────────────────────────
// Exported for C code compatibility. Writes char to 0x10000000.
.global asm_uart_putchar
asm_uart_putchar:
    li   t0, 0x10000000
    sb   a0, 0(t0)
    ret
