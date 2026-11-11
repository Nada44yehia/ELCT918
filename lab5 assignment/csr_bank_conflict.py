"""
csr_bank_conflict.py -- assignment example:
"Show with an example why unstructured sparsity in CSR format would cause
 bank conflicts in this datapath."

Datapath rule (from design.sv):
  * vector_buffer has 4 banks, bank b holds vector[8b .. 8b+7]
  * each bank has ONE read port  -> one value per bank per cycle
  * MAC lane b is wired to bank b only

The script prunes the SAME row two ways (both keep 16 of 32 = 50 %):
  1. FSS  : 4 largest |w| in every bank        -> stored as CSB
  2. Unstructured : 16 largest |w| of the row  -> stored as CSR
and counts the cycles needed to read the vector values for each.

Usage:
  py csr_bank_conflict.py              # seed 17 = notebook data (271)
  py csr_bank_conflict.py --seed 5     # another row
  py csr_bank_conflict.py --stats 100  # average over 100 random rows
"""
import argparse
import numpy as np

NUM_BANKS, BANK_SIZE, KEEP_PER_BANK = 4, 8, 4
ROW_SIZE = NUM_BANKS * BANK_SIZE          # 32
NNZ = NUM_BANKS * KEEP_PER_BANK           # 16 kept weights
LANES = 4                                 # 4 MAC lanes


def bank_of(col):
    """Bank of a global column = col // 8  (vec_waddr[4:3] in hardware)."""
    return col // BANK_SIZE


def make_row(seed):
    """Same generator as the notebook and run_on_fpga.py."""
    rng = np.random.default_rng(seed)
    w = rng.integers(-12, 13, size=ROW_SIZE, dtype=np.int16)
    v = rng.integers(-10, 11, size=ROW_SIZE, dtype=np.int16)
    return w, v


def fss_cols(row):
    """FSS: keep the 4 largest |w| inside each bank."""
    cols = []
    for b in range(NUM_BANKS):
        bank = row[b * BANK_SIZE:(b + 1) * BANK_SIZE]
        sel = np.sort(np.argsort(-np.abs(bank), kind="stable")[:KEEP_PER_BANK])
        cols += [b * BANK_SIZE + int(s) for s in sel]
    return sorted(cols)


def unstructured_cols(row):
    """Unstructured: keep the 16 largest |w| of the whole row."""
    sel = np.argsort(-np.abs(row), kind="stable")[:NNZ]
    return sorted(int(c) for c in sel)


def csr_issue_cycles(cols):
    """CSR order, 4 entries fetched per group; k reads to the same bank
    in one group need k cycles (one read port per bank)."""
    total, rows = 0, []
    for g in range(0, len(cols), LANES):
        grp = cols[g:g + LANES]
        reads = [sum(bank_of(c) == b for c in grp) for b in range(NUM_BANKS)]
        total += max(reads)
        rows.append((g // LANES, grp, reads, max(reads)))
    return total, rows


def per_bank(cols):
    return [sum(bank_of(c) == b for c in cols) for b in range(NUM_BANKS)]


def show_example(seed):
    w, v = make_row(seed)
    line = "=" * 72

    print(line)
    print(f"ORIGINAL ROW (seed {seed}), split into 4 banks of 8")
    print(line)
    for b in range(NUM_BANKS):
        print(f"bank {b} (cols {8*b:2d}-{8*b+7:2d}): {w[8*b:8*b+8].tolist()}")

    # ---------------- 1. FSS + CSB ----------------
    f = fss_cols(w)
    print("\n" + line)
    print("1) FSS pruning (4 largest |w| per bank)  ->  CSB format")
    print(line)
    print(f"non-zeros per bank : {per_bank(f)}")
    print("CSB groups (one weight from EACH bank per group):")
    by_bank = [[c for c in f if bank_of(c) == b] for b in range(NUM_BANKS)]
    for k in range(KEEP_PER_BANK):
        cols = [by_bank[b][k] for b in range(NUM_BANKS)]
        print(f"  group {k}: cols {cols}  -> banks [0, 1, 2, 3]  -> 1 cycle")
    print(f"issue cycles       : {KEEP_PER_BANK}   (no conflicts)")
    print(f"useful MACs/cycle  : {NNZ}/{KEEP_PER_BANK} = {NNZ/KEEP_PER_BANK:.2f}")

    # ---------------- 2. Unstructured + CSR ----------------
    u = unstructured_cols(w)
    pruned_u = np.zeros(ROW_SIZE, dtype=np.int16)
    pruned_u[u] = w[u]
    total, rows = csr_issue_cycles(u)

    print("\n" + line)
    print("2) UNSTRUCTURED pruning (16 largest |w| of the row)  ->  CSR format")
    print(line)
    print(f"non-zeros per bank : {per_bank(u)}   <- unbalanced")
    print("CSR arrays:")
    print(f"  values  = {[int(w[c]) for c in u]}")
    print(f"  col_idx = {u}")
    print(f"  row_ptr = [0, {len(u)}]")
    print("\nCSR fetch, 4 entries per group, ONE read per bank per cycle:")
    print(f"  {'grp':<4}{'col_idx':<20}{'banks':<16}{'reads/bank':<16}cycles")
    for g, grp, reads, cyc in rows:
        banks = [bank_of(c) for c in grp]
        flag = "   <- CONFLICT" if cyc > 1 else ""
        print(f"  {g:<4}{str(grp):<20}{str(banks):<16}{str(reads):<16}{cyc}{flag}")
    worst = max(per_bank(u))
    print(f"\nissue cycles (CSR order)        : {total}")
    print(f"useful MACs/cycle (CSR order)   : {NNZ}/{total} = {NNZ/total:.2f}")
    print(f"best case, perfect reordering   : {worst} cycles "
          f"(busiest bank has {worst} values) -> {NNZ}/{worst} = {NNZ/worst:.2f}")
    print(f"dense baseline, for reference   : 8 cycles -> 16/8 = 2.00")

    # Check both pruned rows give a valid dot product (same math, only layout differs)
    exp_u = int(np.dot(pruned_u.astype(int), v.astype(int)))
    exp_f = int(np.dot(np.where(np.isin(np.arange(ROW_SIZE), f), w, 0).astype(int),
                       v.astype(int)))
    print(f"\nNote: the two rows keep different weights, so their dot products differ")
    print(f"(FSS row = {exp_f}, unstructured row = {exp_u}). Bank conflicts do not change")
    print("the arithmetic: a CSR PE would still compute its own row's value exactly,")
    print("it would only need more cycles. This example compares cycles, not results.")

    # ---------------- 3. SAME FSS row, but stored as CSR ----------------
    total_f, rows_f = csr_issue_cycles(f)
    print("\n" + line)
    print(f"3) SAME FSS row (result {exp_f}) stored in CSR order instead of CSB")
    print(line)
    print(f"  col_idx = {f}")
    print(f"  {'grp':<4}{'col_idx':<20}{'banks':<16}{'reads/bank':<16}cycles")
    for g, grp, reads, cyc in rows_f:
        banks = [bank_of(c) for c in grp]
        flag = "   <- CONFLICT" if cyc > 1 else ""
        print(f"  {g:<4}{str(grp):<20}{str(banks):<16}{str(reads):<16}{cyc}{flag}")
    print(f"issue cycles: {total_f} -> {NNZ}/{total_f} = {NNZ/total_f:.2f} MACs/cycle")
    print("Same weights and same result as the sparse PE, but CSR's column order")
    print("puts neighbouring columns (same bank) in the same group. CSB reorders")
    print("them to one-per-bank, which is what removes the conflicts.")

    # Explain the first conflict in words
    g0 = rows[0]
    if g0[3] > 1:
        b = int(np.argmax(g0[2]))
        print("\n" + line)
        print("WHY: group 0 needs columns "
              f"{g0[1]}; {g0[2][b]} of them are in bank {b}.")
        print(f"Bank {b} has one read port, so the {g0[2][b]} reads are serialised over "
              f"{g0[2][b]} cycles while the other lanes are idle = BANK CONFLICT.")
        print("FSS + CSB avoids this: every group reads banks 0,1,2,3 exactly once.")
        print(line)


def show_stats(n):
    t, m = [], []
    for s in range(1, n + 1):
        w, _ = make_row(s)
        u = unstructured_cols(w)
        t.append(csr_issue_cycles(u)[0])
        m.append(max(per_bank(u)))
    print(f"Unstructured + CSR over {n} random rows (seeds 1..{n}):")
    print(f"  issue cycles (CSR order): mean {np.mean(t):.2f}, min {min(t)}, max {max(t)}")
    print(f"  busiest bank            : mean {np.mean(m):.2f}, min {min(m)}, max {max(m)}")
    print(f"  rows with conflicts     : {sum(x > KEEP_PER_BANK for x in t)}/{n}")
    print(f"FSS + CSB: always {KEEP_PER_BANK} cycles, 0 conflicts.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=17)
    ap.add_argument("--stats", type=int, default=0, help="average over N random rows")
    a = ap.parse_args()
    if a.stats:
        show_stats(a.stats)
    else:
        show_example(a.seed)


if __name__ == "__main__":
    main()