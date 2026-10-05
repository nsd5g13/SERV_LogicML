# Popcount Benchmark Results

Compare three popcount implementations on the same 5-word input array:

```c
arr[5] = { 0x00000000, 0xFFFFFFFF, 0xDEADBEEF, 0x55555555, 0xAAAAAAAA }
// expected total popcount = 0 + 32 + 24 + 16 + 16 = 88 = 0x58
```

All three rounds verified correct: signature (write to 0x80000000) = 0x58 = 88.

## Result

| Round | Version | RTL (submodule) | Test file | START | END | Cycles | Instr |
|-------|---------|-----------------|-----------|-------|-----|--------|-------|
| 1 | Software popcount (32-bit loop) | `e81a9cf` (any) | `popcount_bench_sw/popcount_sw_bench.c` | `0x48` | `0x88` | 40860 | 836 |
| 2 | Custom instr V1 (register popcount) | `ac5aa03` (Phase-1) | `popcount_bench_v1/popcount_v1_bench.c` | `0x48` | `0x94` | 914 | 20 |
| 3 | Custom instr V2 (memory-range popcount) | `e81a9cf` (Phase-2) | `popcount_bench_v2/popcount_v2_bench.c` | `0x48` | `0x5c` | 464 | 6 |

## Cycle-count measurement method

- **START = `0x48`**: main() entry — the first instruction of the popcount computation for all three versions.
- **END**: the result store `sb total, 0(0x80000000)` (SW `0x88`, V1 `0x94`, V2 `0x5c`). The halt setup/overhead is excluded so all rounds measure the same "compute + store result" region.
- Cycles summed from each round's `compare_result.txt` (`PC -> Next PC : cycles` lines within [START, END]).
- All three mains are structurally identical at the C level; only `popcount_all()` differs.

## Speedup (vs software)

| Version | Cycles | vs SW |
|---------|--------|-------|
| Software | 40860 | 1.00x |
| V1 register popcount | 914 | **44.7x** |
| V2 memory-range popcount | 464 | **88.1x** |

## Notes

- **V1 vs V2 form difference is inherent**: V1 processes one 32-bit register per instruction (the compiler fully unrolled 5 calls + inline constant loads, hence 20 instructions), while V2 processes the whole memory range in one instruction (the `.insn` at `0x50` alone takes ~250 cycles = 5 words × (mem_read + 32-cycle acc) + write_back).
- Round 2 requires the Phase-1 RTL (`ac5aa03`) because the current RTL (`e81a9cf`) interprets V1's encoding (`rs2=x0`) as a range popcount from address `rs1` to `0`, not a register popcount. Verified: V1 signature = 0x58 on the Phase-1 fusesoc binary.
- Each round's `compare_result.txt`, `firmware.dump`, and `sim_log.txt` are preserved under `roundN_*/`.
