# ELCT918 – Black-Box Reverse Engineering

## Description

This project reverse-engineers the given `mystery` Verilog module and implements an equivalent readable RTL model.

The main behavior is:

- `rst_n` is an active-low reset.
- `en` controls when the circuit updates.
- `dout[7:4]` is an enabled-cycle counter.
- `dout[3:0]` is generated from `din` using a repeating offset sequence `6, 7, 4, 5`.
- `flag` becomes `1` when the ciphertext sequence `CAFE` is detected.
- The input sequence that generates `CAFE` is **`63B9`**.

## Files

```text
design.v      # the unchanged mystery module and the solution 
soultion.v     # Reverse-engineered RTL
test_bench.v   # Experiments testbench
self_checking_tb.v   # Self-checking testbench
README.md      # Project documentation
```

## Running on EDA Playground

1. Open **EDA Playground**: https://www.edaplayground.com/
2. Create a new playground.
3. Select **SystemVerilog/Verilog** as the language.
4. Select a simulator  ** Icarus Verilog 12.0**.
5. Copy the contents of:
   - `design.v`
   - `self_checking_tb.v`
   into the appropriate files in EDA Playground.
6. Set the **top-level testbench** to `self_checking_tb`.
7. Click **Run**.
8. Check the console output for the test results.

The testbench performs randomized verification and compares the outputs of the original `mystery` module with the reverse-engineered `solution` module.

A successful verification should report:

```text
PASS: No mismatches detected.
```

The testbench also checks the password sequence:

```text
Input:  6 3 B 9
Output: 1C 2A 3F 4E
Flag:   0 0 0 1
```
