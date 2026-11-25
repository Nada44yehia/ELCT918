# Vivado 2020.1 non-project BRAM design space exploration
# Usage: vivado -mode batch -source scripts/bram_sweep.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7a100tcsg324-1
set out [file join $root reports bram]
file mkdir $out
set csv [open [file join $out results.csv] w]
puts $csv "DATA_W,DEPTH,RAMB36,RAMB18,Tiles,LUT_cells,LUTRAM_cells,WNS_ns,Efficiency_pct,Status"
flush $csv

proc trial {w d} {
    global root part out csv
    set dir [file join $out W${w}_D${d}]
    file mkdir $dir
    cd $dir
    set f [open init.mem w]
    set digits [expr {($w+3)/4}]
    set mask [expr {(1 << $w)-1}]
    set x 123456789
    for {set i 0} {$i < $d} {incr i} {
        set x [expr {(6364136223846793005*$x+1442695040888963407) & 0x7fffffffffffffff}]
        puts $f [format %0*llx $digits [expr {($x >> 16) & $mask}]]
    }
    close $f
    set r36 {}; set r18 {}; set tiles {}; set lut {}; set lutram {}; set wns {}; set eff {}
    set stage setup
    set status OK
    puts "=== WIDTH $w DEPTH $d ==="
    if {[catch {
        create_project -in_memory -part $part
        read_verilog [file join $root rtl BRAM_top_initialized.v]
        read_verilog [file join $root rtl bram_dse_top.v]
        read_xdc [file join $root constraints bram_dse.xdc]
        set stage synthesis
        synth_design -top bram_dse_top -part $part -mode out_of_context -generic [list DATA_W=$w DEPTH=$d]
        report_utilization -file synth_util.rpt
        set stage optimization
        opt_design
        set r36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
        set r18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
        set tiles [expr {$r36+$r18/2.0}]
        set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
        set lutram [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAM* && REF_NAME !~ RAMB*}]]
        if {$tiles > 0} {set eff [format %.4f [expr {100.0*$w*$d/($tiles*36864)}]]}
        set stage placement
        place_design
        set stage routing
        route_design
        set stage reporting
        report_utilization -file util.rpt
        report_timing_summary -file timing.rpt
        set paths [get_timing_paths -quiet -delay_type max -max_paths 1]
        if {[llength $paths]} {set wns [get_property SLACK [lindex $paths 0]]}
        set r36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
        set r18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
        set tiles [expr {$r36+$r18/2.0}]
        set lut [llength [get_cells -quiet -hier -filter {REF_NAME =~ LUT*}]]
        set lutram [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAM* && REF_NAME !~ RAMB*}]]
        if {$tiles > 0} {set eff [format %.4f [expr {100.0*$w*$d/($tiles*36864)}]]}
        if {$lutram > 0 || $tiles == 0 || ($w*double($d) > $tiles*36864)} {set status NOT_ALL_BRAM} elseif {$wns eq {}} {set status NO_TIMING} elseif {$wns < 0} {set status TIMING_FAIL}
    } err]} {
        set status FAIL_$stage
        set e [open error.txt w]; puts $e $err; close $e
        puts "FAILED: $err"
    }
    puts $csv [join [list $w $d $r36 $r18 $tiles $lut $lutram $wns $eff $status] ,]
    flush $csv
    catch {close_project}
    cd $root
    # Retain reports, not the large generated initialization files.
    file delete -force [file join $dir init.mem]
    return $status
}

# First run a small pilot; pass full as a Tcl argument for the complete sweep.
if {[llength $argv] == 0 || [lindex $argv 0] ne "full"} {
    trial 32 4096
} else {
    foreach {w depths} {
        8  {65536 131072 262144 524288 552960 557056}
        16 {32768 65536 131072 262144 276480 278528}
        18 {32768 65536 131072 262144 276480 278528}
        32 {16384 32768 65536 131072 138240 139264}
        36 {16384 32768 65536 131072 138240 139264}
    } {
        foreach d $depths {trial $w $d}
    }
}
close $csv
puts "Results: [file join $out results.csv]"
