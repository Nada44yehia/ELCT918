"""
run_on_fpga.py -- send FSS/CSB data to the sparse PE on the Nexys4 DDR over
UART and read the result back.

Run it on the laptop that is connected to the board (not on Colab).

Setup (once):
    pip install pyserial numpy

Find the board's COM port:
    python -m serial.tools.list_ports
    (or Windows Device Manager -> Ports (COM & LPT) -> "USB Serial Port (COMx)")

Usage (board programmed with the SPARSE bitstream):
    python run_on_fpga.py --port COM5                # same data as the notebook -> 271
    python run_on_fpga.py --port COM5 --seed 3       # another random row
    python run_on_fpga.py --port COM5 --runs 100     # 100 random rows, PASS/FAIL count

Usage (board programmed with the BASELINE bitstream):
    python run_on_fpga.py --port COM5 --pe baseline
    python run_on_fpga.py --port COM5 --pe baseline --runs 100
"""

import argparse
import struct
import sys
import time

import numpy as np
import serial

# ============================================================
# Same configuration as the notebook (Topic 6 / FSS)
# ============================================================
NUM_BANKS = 4
BANK_SIZE = 8
ROW_SIZE = NUM_BANKS * BANK_SIZE
KEEP_PER_BANK = 4

HDR_SPARSE = 0xA5                      # header for the sparse PE bitstream
HDR_BASELINE = 0xB5                    # header for the baseline PE bitstream
HDR_FROM_FPGA = 0x5A
PACKET_LEN = 69                        # same length for both PEs
REPLY_LEN = 6                          # header + result(4) + latency(1)


def fss_csb_encode(row):
    """FSS pruning + CSB encoding, identical to the notebook."""
    pruned = np.zeros(ROW_SIZE, dtype=np.int16)
    bank_kept_values = []
    bank_kept_indices = []

    for b in range(NUM_BANKS):
        bank = row[b * BANK_SIZE:(b + 1) * BANK_SIZE]
        selected = np.argsort(-np.abs(bank), kind="stable")[:KEEP_PER_BANK]
        selected = np.sort(selected)
        bank_kept_values.append(bank[selected])
        bank_kept_indices.append(selected)
        pruned[b * BANK_SIZE + selected] = bank[selected]

    csb_weights = np.zeros((KEEP_PER_BANK, NUM_BANKS), dtype=np.int16)
    csb_indices = np.zeros((KEEP_PER_BANK, NUM_BANKS), dtype=np.uint8)
    for k in range(KEEP_PER_BANK):
        for b in range(NUM_BANKS):
            csb_weights[k, b] = bank_kept_values[b][k]
            csb_indices[k, b] = bank_kept_indices[b][k]

    return pruned, csb_weights, csb_indices


def make_data(seed):
    """Same random generation as the notebook (seed 17 -> expected 271)."""
    rng = np.random.default_rng(seed)
    weights = rng.integers(-12, 13, size=ROW_SIZE, dtype=np.int16)
    vector = rng.integers(-10, 11, size=ROW_SIZE, dtype=np.int16)

    pruned, csb_w, csb_i = fss_csb_encode(weights)
    expected = sum(int(w) * int(x) for w, x in zip(pruned, vector))
    return vector, pruned, csb_w, csb_i, expected


def build_packet_sparse(vector, csb_w, csb_i, expected):
    """69 bytes: A5 | vector[32] | CSB weights[16] | CSB indices[16] | expected (LE)."""
    pkt = bytearray([HDR_SPARSE])
    pkt += bytes(int(v) & 0xFF for v in vector)                 # signed INT8
    pkt += bytes(int(w) & 0xFF for w in csb_w.reshape(-1))      # [group][bank] order
    pkt += bytes(int(i) & 0x07 for i in csb_i.reshape(-1))      # 3-bit local index
    pkt += struct.pack("<i", expected)
    assert len(pkt) == PACKET_LEN
    return bytes(pkt)


def build_packet_baseline(vector, pruned, expected):
    """69 bytes: B5 | vector[32] | pruned dense weights[32] | expected (LE)."""
    pkt = bytearray([HDR_BASELINE])
    pkt += bytes(int(v) & 0xFF for v in vector)                 # signed INT8
    pkt += bytes(int(w) & 0xFF for w in pruned)                 # dense row, zeros included
    pkt += struct.pack("<i", expected)
    assert len(pkt) == PACKET_LEN
    return bytes(pkt)


def run_once(ser, seed, pe="sparse", verbose=True):
    vector, pruned, csb_w, csb_i, expected = make_data(seed)

    if pe == "sparse":
        packet = build_packet_sparse(vector, csb_w, csb_i, expected)
    else:
        packet = build_packet_baseline(vector, pruned, expected)

    ser.reset_input_buffer()
    t0 = time.perf_counter()
    ser.write(packet)
    reply = ser.read(REPLY_LEN)
    t1 = time.perf_counter()

    if len(reply) != REPLY_LEN or reply[0] != HDR_FROM_FPGA:
        raise RuntimeError(
            f"No valid reply from FPGA (got {len(reply)} bytes: {reply.hex()}). "
            f"Check the COM port, that the board has the {pe.upper()} bitstream "
            "(use --pe sparse / --pe baseline to match it), and press CPU RESET."
        )

    fpga_result, latency = struct.unpack("<iB", reply[1:])
    ok = fpga_result == expected

    if verbose:
        print("------------------------------------------")
        print(f"PE on the board    = {pe.upper()}")
        print(f"Seed               = {seed}")
        print(f"Vector             = {vector.tolist()}")
        if pe == "sparse":
            print(f"CSB weights        =\n{csb_w}")
            print(f"CSB indices        =\n{csb_i}")
        else:
            print(f"Pruned weights     = {pruned.tolist()}")
        print("------------------------------------------")
        print(f"Python expected    = {expected}")
        print(f"FPGA result        = {fpga_result}")
        print(f"FPGA latency       = {latency} cycles (13 ns clock)")
        print(f"Round trip (UART)  = {(t1 - t0) * 1e3:.1f} ms")
        print("TEST PASSED: FPGA matches Python." if ok else "TEST FAILED: mismatch!")
        print("------------------------------------------")

    return ok, fpga_result, expected, latency


def main():
    ap = argparse.ArgumentParser(description="Run the sparse PE on the FPGA over UART.")
    ap.add_argument("--port", required=True, help="COM port, e.g. COM5 or /dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--seed", type=int, default=17, help="17 = notebook data (271)")
    ap.add_argument("--runs", type=int, default=1, help="number of random rows to test")
    ap.add_argument("--pe", choices=["sparse", "baseline"], default="sparse",
                    help="which bitstream is on the board")
    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, timeout=2) as ser:
        time.sleep(0.1)

        if args.runs == 1:
            ok, *_ = run_once(ser, args.seed, pe=args.pe, verbose=True)
            sys.exit(0 if ok else 1)

        passed = 0
        print(f"PE on the board = {args.pe.upper()}")
        for s in range(args.seed, args.seed + args.runs):
            ok, res, exp, lat = run_once(ser, s, pe=args.pe, verbose=False)
            passed += ok
            print(f"seed {s:4d}: expected {exp:7d}  fpga {res:7d}  "
                  f"latency {lat} cycles  {'PASS' if ok else 'FAIL'}")
        print("------------------------------------------")
        print(f"{passed}/{args.runs} rows passed")
        sys.exit(0 if passed == args.runs else 1)


if __name__ == "__main__":
    main()
