/*
 * Linker script for PicoRV32 simulation testbench.
 *
 * Memory map:
 *   0x00000000 - 0x00017FFF: Code, constants (rodata), data, and BSS (96 KB)
 *   0x00018000 - 0x0001FFFF: Stack space (32 KB, growing down from 0x00020000)
 */

MEMORY {
	mem : ORIGIN = 0x00000000, LENGTH = 0x00018000
}

SECTIONS {
	.memory : {
		. = 0x000000;
		start*(.text);
		*(.text .text.*);
		*(.rodata .rodata.*);
		. = ALIGN(16);
		/* 16 bytes of zeros to cleanly terminate table/tree lookups */
		LONG(0);
		LONG(0);
		LONG(0);
		LONG(0);
		*(.data .data.*);
		*(.sdata .sdata.*);
		. = ALIGN(4);
		_sbss = .;
		*(.sbss .sbss.*);
		*(.bss .bss.*);
		*(COMMON);
		. = ALIGN(4);
		_ebss = .;
		. = ALIGN(16);
		end = .;
	} > mem

	/DISCARD/ : {
		*(.comment)
		*(.comment.*)
		*(.note*)
		*(.riscv.attributes)
		*(.eh_frame*)
	}
}
