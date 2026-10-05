/*
 * sim_main.cpp — Verilator testbench for SERV (servant_sim top module)
 *
 * Monitors PC address changes during simulation and reports the cycle cost
 * for each instruction, i.e. for every PC transition:
 *
 *     last_pc -> current_pc : N cycles
 *
 * Uses the full servant_sim SoC which includes the SERV CPU core, RAM,
 * timer, GPIO, and bus mux.
 *
 * Build & run: ./run_sim.sh
 */

#include <iostream>
#include <fstream>
#include <memory>
#include <cstdint>
#include <iomanip>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include "Vservant_sim.h"  // Auto-generated header by Verilator for servant_sim
#include "verilated.h"
#include "verilated_vcd_c.h"  // VCD trace support

// Required by Verilator when $time is referenced in Verilog
static uint64_t sim_time = 0;
double sc_time_stamp() { return sim_time; }

int main(int argc, char** argv) {
    // ── Redirect stdout to log file ──────────────────────────
    mkdir("log", 0755);  // Ensure log/ directory exists
    const char* logfile = "log/sim_log.txt";
    std::ofstream ofs(logfile);
    if (!ofs) {
        std::cerr << "[ERROR] Cannot open log file: " << logfile << std::endl;
        return 1;
    }
    // Save original cout buffer so we can restore it before ofs is destroyed
    std::streambuf* orig_buf = std::cout.rdbuf(ofs.rdbuf());

    // ── Initialise Verilator and the top-level module ────────
    Verilated::commandArgs(argc, argv);
    auto top = std::make_unique<Vservant_sim>();

    // ── VCD trace setup ─────────────────────────────────────
    VerilatedVcdC* tfp = nullptr;
    {
        const char* vcd_arg = Verilated::commandArgsPlusMatch("vcd=");
        if (vcd_arg[0]) {
            Verilated::traceEverOn(true);
            tfp = new VerilatedVcdC;
            top->trace(tfp, 99);       // Trace 99 levels of hierarchy
            tfp->open("log/sim_wave.vcd");
            std::cout << "[VCD] Tracing enabled -> log/sim_wave.vcd" << std::endl;
        }
    }

    // ── PC trace binary file setup ──────────────────────────
    int trace_fd = -1;
    {
        const char* trace_arg = Verilated::commandArgsPlusMatch("trace_pc=");
        if (trace_arg[0]) {
            const char* trace_path = "build/award-winning_serv_servant_1.4.0/verilator_tb/trace.bin";
            // Ensure parent directory exists
            mkdir("build", 0755);
            mkdir("build/award-winning_serv_servant_1.4.0", 0755);
            mkdir("build/award-winning_serv_servant_1.4.0/verilator_tb", 0755);
            trace_fd = open(trace_path, O_WRONLY | O_CREAT | O_TRUNC, S_IRWXU);
            if (trace_fd < 0) {
                std::cerr << "[WARN] Cannot open " << trace_path << " for writing" << std::endl;
            } else {
                std::cout << "[Trace] Writing PC trace -> " << trace_path << std::endl;
            }
        }
    }

    // Simulation state
    uint64_t main_time     = 0;  // Half-cycle time counter
    uint64_t current_cycle = 0;  // Rising-edge cycle counter

    // PC monitoring state
    uint32_t last_pc       = 0;
    uint64_t start_cycle   = 0;
    bool have_last_pc      = false;

    // ── Reset phase ──────────────────────────────────────────
    // servant_sim uses wb_clk / wb_rst, active-high reset
    top->wb_clk = 0;
    top->wb_rst = 1;

    for (int i = 0; i < 20; i++) {
        top->wb_clk = !top->wb_clk;
        top->eval();
        main_time++;
    }

    top->wb_rst = 0;  // Release reset

    std::cout << "[Monitor] Reset complete. Watching for PC changes..."
              << std::endl;

    // Safety limit to prevent infinite simulation
    const uint64_t MAX_CYCLES = 10000000;

    // ── Main simulation loop ─────────────────────────────────
    while (!Verilated::gotFinish() && current_cycle < MAX_CYCLES) {
        top->wb_clk = !top->wb_clk;  // Toggle clock
        top->eval();                 // Propagate combinational logic

        // Dump VCD on every half-cycle
        if (tfp) tfp->dump(main_time);

        // Only sample signals on the rising clock edge
        if (top->wb_clk == 1) {
            current_cycle++;

            /*
             * pc_vld indicates that pc_adr holds a valid PC address
             * in this cycle.
             */
            if (top->pc_vld) {
                uint32_t current_pc = top->pc_adr;

                // Write raw PC to trace.bin for post-processing
                if (trace_fd >= 0) {
                    if (write(trace_fd, &current_pc, 4) < 0) {
                        std::cerr << "[WARN] Failed to write trace.bin" << std::endl;
                        close(trace_fd);
                        trace_fd = -1;
                    }
                }

                /*
                 * First valid PC:
                 * Only use it as the baseline.
                 * Do not print, because there is no previous PC yet.
                 */
                if (!have_last_pc) {
                    last_pc = current_pc;
                    start_cycle = current_cycle;
                    have_last_pc = true;

                    std::cout << std::hex
                              << "[Monitor] First valid PC = 0x"
                              << last_pc
                              << std::dec
                              << " at cycle "
                              << start_cycle
                              << std::endl;
                }

                /*
                 * Subsequent PC change:
                 * The elapsed cycles from start_cycle to current_cycle
                 * correspond to the cost of executing the instruction
                 * located at last_pc.
                 */
                else if (current_pc != last_pc) {
                    uint64_t delta_cycles = current_cycle - start_cycle;

                    std::cout << std::hex
                              << "0x" << last_pc
                              << " -> 0x" << current_pc
                              << std::dec
                              << " : " << delta_cycles
                              << " cycles"
                              << std::endl;

                    // Update baseline for the next instruction
                    last_pc = current_pc;
                    start_cycle = current_cycle;
                }
            }
        }

        main_time++;
        sim_time = main_time;  // Keep sc_time_stamp() in sync
    }

    // ── Simulation end ───────────────────────────────────────
    if (current_cycle >= MAX_CYCLES) {
        std::cout << "[Monitor] Reached max cycles ("
                  << MAX_CYCLES
                  << "). Exiting."
                  << std::endl;
    }

    // Flush and close VCD trace
    if (tfp) {
        tfp->flush();
        tfp->close();
        std::cout << "[VCD] Trace file closed: log/sim_wave.vcd" << std::endl;
    }

    // Close PC trace binary
    if (trace_fd >= 0) {
        close(trace_fd);
        std::cout << "[Trace] PC trace saved: trace.bin" << std::endl;
    }

    top->final();

    // Restore original cout buffer before ofs is destroyed
    std::cout.rdbuf(orig_buf);
    return 0;
}