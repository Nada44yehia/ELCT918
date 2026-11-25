# -----------------------------------------------------------------------------
# sweep_template.tcl  --  Vivado non-project batch flow for the Task 4 DSE
# Run from this folder's parent:  vivado -mode batch -source scripts/sweep_template.tcl
# Adapt: top module name, generic name(s), sweep values, constraint file.
# -----------------------------------------------------------------------------
set part xc7a100tcsg324-1
file mkdir reports

read_verilog [glob ./rtl/*.v]
read_xdc ./constraints/pe_array.xdc        ;# your constraints for the PE array

foreach n {1 2 4 8 16 32 64 128} {
    synth_design -top pe_array -part $part -generic N_PE=$n
    opt_design
    place_design
    route_design
    report_utilization    -file reports/util_N$n.rpt
    report_timing_summary -file reports/timing_N$n.rpt
    report_power          -file reports/power_N$n.rpt
}
