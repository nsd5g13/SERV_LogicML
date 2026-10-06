#!/usr/bin/env python3

"""
debug_dump.py

Find every occurrence where:

    wb_mem_adr[31:0] == 0x40101200

but capture wb_mem_dat[31:0] only on the FIRST cycle
of each occurrence.

Example:

    cycle   address       data
    100     0x12345678    ...
    101     0x40101200    0x00000002  <- capture
    102     0x40101200    0x00000002  <- ignore
    103     0x40101200    0x00000002  <- ignore
    104     0x12345678    ...
    105     0x40101200    0x00000001  <- capture

Output:
    debug.text
"""

import sys
from pathlib import Path

from vcdvcd import VCDVCD


# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent.parent

DEFAULT_VCD = (
    SCRIPT_DIR
    / "build"
    / "award-winning_serv_servant_1.4.0"
    / "verilator_tb"
    / "simulation.vcd"
)

DEFAULT_OUT = SCRIPT_DIR / "debug.text"


# ------------------------------------------------------------
# Target signals
# ------------------------------------------------------------

TARGET_ADDRESS = 0x40101200

ADDRESS_SIGNAL = "TOP.servant_sim.dut.wb_mem_adr[31:0]"
DATA_SIGNAL = "TOP.servant_sim.dut.wb_mem_dat[31:0]"


# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

def parse_args():

    vcd_file = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else DEFAULT_VCD
    )

    output_file = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else DEFAULT_OUT
    )

    return vcd_file, output_file


# ------------------------------------------------------------
# Convert VCD binary value
# ------------------------------------------------------------

def binary_to_int(value):

    if value is None:
        return None

    value = str(value)

    if any(c in value.lower() for c in ("x", "z")):
        return None

    try:
        return int(value, 2)
    except ValueError:
        return None


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

def find_debug_transactions(vcd_file, output_file):

    print(f"VCD file : {vcd_file}")
    print(f"Output   : {output_file}")
    print(f"Address  : 0x{TARGET_ADDRESS:08x}")
    print()

    if not vcd_file.exists():
        print(f"ERROR: VCD file not found:")
        print(f"  {vcd_file}")
        sys.exit(1)

    print("Reading VCD...")

    try:
        vcd = VCDVCD(
            str(vcd_file),
            store_tvs=True
        )

    except Exception as e:
        print(f"ERROR: could not read VCD:")
        print(f"  {e}")
        sys.exit(1)

    # --------------------------------------------------------
    # Check address signal
    # --------------------------------------------------------

    if ADDRESS_SIGNAL not in vcd.signals:

        print()
        print("ERROR: address signal not found:")
        print(f"  {ADDRESS_SIGNAL}")
        print()
        print("Available wb_mem_adr signals:")

        for signal in vcd.signals:
            if "wb_mem_adr" in signal:
                print(f"  {signal}")

        sys.exit(1)

    # --------------------------------------------------------
    # Check data signal
    # --------------------------------------------------------

    if DATA_SIGNAL not in vcd.signals:

        print()
        print("ERROR: data signal not found:")
        print(f"  {DATA_SIGNAL}")
        print()
        print("Available wb_mem_dat signals:")

        for signal in vcd.signals:
            if "wb_mem_dat" in signal:
                print(f"  {signal}")

        sys.exit(1)

    # --------------------------------------------------------
    # Get transitions
    # --------------------------------------------------------

    address_tv = vcd[ADDRESS_SIGNAL].tv
    data_tv = vcd[DATA_SIGNAL].tv

    # --------------------------------------------------------
    # Walk through address transitions
    #
    # We only capture when the address CHANGES INTO
    # TARGET_ADDRESS.
    # --------------------------------------------------------

    results = []

    previous_address = None

    for timestamp, address_binary in address_tv:

        address = binary_to_int(address_binary)

        if address is None:
            previous_address = address
            continue

        # ----------------------------------------------------
        # Detect transition INTO target address
        # ----------------------------------------------------

        if (
            address == TARGET_ADDRESS
            and previous_address != TARGET_ADDRESS
        ):

            # ------------------------------------------------
            # Get wb_mem_dat value at this timestamp.
            #
            # VCD signal values are piecewise constant.
            # Find the latest data value at or before timestamp.
            # ------------------------------------------------

            data_binary = None

            for data_time, data_value in data_tv:

                if data_time > timestamp:
                    break

                data_binary = data_value

            data_value = binary_to_int(data_binary)

            results.append(
                (
                    timestamp,
                    data_value,
                    data_binary,
                )
            )

        previous_address = address

    # --------------------------------------------------------
    # Write output
    # --------------------------------------------------------

    with open(output_file, "w") as f:

        f.write("SERV Debug Mailbox Trace\n")
        f.write("========================\n\n")

        f.write(
            f"Target address: 0x{TARGET_ADDRESS:08x}\n"
        )

        f.write(
            f"Occurrences: {len(results)}\n\n"
        )

        f.write(
            f"{'Cycle':>12}  {'Address':>12}  {'Data':>12}\n"
        )

        f.write(
            f"{'-' * 12}  {'-' * 12}  {'-' * 12}\n"
        )

        for timestamp, data_value, data_binary in results:

            if data_value is not None:
                data_string = f"0x{data_value:08x}"
            else:
                data_string = str(data_binary)

            f.write(
                f"{timestamp:12d}  "
                f"0x{TARGET_ADDRESS:08x}  "
                f"{data_string}\n"
            )

    # --------------------------------------------------------
    # Print summary
    # --------------------------------------------------------

    print()
    print(f"Found {len(results)} occurrence(s).")
    if len(results) == 0:
        print("Enable or correct the debug option in the C source code.")

    for timestamp, data_value, data_binary in results:

        if data_value is not None:
            print(
                f"  cycle {timestamp}: "
                f"wb_mem_dat = 0x{data_value:08x}"
            )
        else:
            print(
                f"  cycle {timestamp}: "
                f"wb_mem_dat = {data_binary}"
            )

    print()
    print(f"Written to: {output_file}")


# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------

if __name__ == "__main__":

    vcd_path, output_path = parse_args()

    find_debug_transactions(
        vcd_path,
        output_path
    )