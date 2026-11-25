# Vivado 2020.1: sparse PE design-space sweep.
# argv: pilot (default), full, or single <dsp|lut|dsp_scratch|lut_scratch> <N>
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7a100tcsg324-1
set out [file join $root reports pe_80MHz]
file mkdir $out
if {[llength [get_projects -quiet]]} {error "Close the current Vivado project before sourcing this script."}
set csvpath [file join $out results.csv]
set newcsv [expr {![file exists $csvpath] || [file size $csvpath] == 0}]
set csv [open $csvpath a]
if {$newcsv} {puts $csv "Variant,N_PE,LUT,FF,DSP,RAMB36,RAMB18,BRAM_tiles,LUT_pct,FF_pct,DSP_pct,BRAM_pct,WNS_ns,WHS_ns,Power_W,Status"}
flush $csv

# Parse the resource count from the standard Vivado utilization table.
proc table_value {report label} {
    foreach line [split $report "\n"] {
        set fields [split $line |]
        if {[llength $fields] > 3 && [string trim [lindex $fields 1]] eq $label} {
            return [string map {, ""} [string trim [lindex $fields 2]]]
        }
    }
    return {}
}
proc read_text {path} {
    set f [open $path r]; set t [read $f]; close $f; return $t
}
proc counts {report} {
    set lut [table_value $report "Slice LUTs"]
    set ff [table_value $report "Slice Registers"]
    set dsp [llength [get_cells -quiet -hier -filter {REF_NAME == DSP48E1}]]
    set r36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
    set r18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
    set tiles [expr {$r36 + $r18/2.0}]
    return [list $lut $ff $dsp $r36 $r18 $tiles]
}
proc percent {n capacity} {
    if {$n eq {}} {return {}}
    return [format %.4f [expr {100.0*$n/$capacity}]]
}
proc trial {variant n} {
    global root part out csv
    set dir [file join $out ${variant}_N${n}]
    file mkdir $dir
    cd $dir
    set lut {}; set ff {}; set dsp {}; set r36 {}; set r18 {}; set tiles {}
    set wns {}; set whs {}; set power {}; set status OK; set stage setup
    set scratch [expr {[string match *_scratch $variant] ? 1 : 0}]
    set islut [string match lut* $variant]
    puts "=== $variant N_PE=$n ==="
    if {[catch {
        create_project -in_memory -part $part
        read_verilog -sv [file join $root rtl sparse_pe_dse.sv]
        read_verilog -sv [file join $root rtl pe_array.sv]
        read_xdc [file join $root constraints pe_array.xdc]
        set stage synthesis
        set args [list -top pe_array -part $part -generic [list N_PE=$n SCRATCH=$scratch]]
        if {$islut} {
        lappend args -verilog_define PE_LUT=1 -max_dsp 0
        }
        synth_design {*}$args
        report_utilization -file synth_util.rpt
        lassign [counts [read_text synth_util.rpt]] lut ff dsp r36 r18 tiles
        set stage optimization
        opt_design
        report_utilization -file opt_util.rpt
        lassign [counts [read_text opt_util.rpt]] lut ff dsp r36 r18 tiles
        set stage placement
        place_design
        set stage routing
        route_design
        set stage reporting
        report_utilization -file util.rpt
        report_utilization -hierarchical -file util_hier.rpt
        report_timing_summary -file timing.rpt
        report_route_status -file route_status.rpt
        report_power -file power.rpt
        lassign [counts [read_text util.rpt]] lut ff dsp r36 r18 tiles
        set paths [get_timing_paths -quiet -delay_type max -max_paths 1]
        if {[llength $paths]} {set wns [get_property SLACK [lindex $paths 0]]}
        set paths [get_timing_paths -quiet -delay_type min -max_paths 1]
        if {[llength $paths]} {set whs [get_property SLACK [lindex $paths 0]]}
        set power_report [read_text power.rpt]
        regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $power_report dummy power
        if {$wns eq {} || $whs eq {}} {
            set status NO_TIMING
        } elseif {$wns < 0 || $whs < 0} {
            set status TIMING_FAIL
        } elseif {($islut && $dsp != 0) || (!$islut && $dsp < 4*$n)} {
            set status DSP_MAPPING_CHECK
        } elseif {$scratch && $tiles < $n/2.0} {
            set status SCRATCH_MAPPING_CHECK
        }
    } err]} {
        set status FAIL_$stage
        set f [open error.txt w]; puts $f $err; close $f
        puts "FAILED: $err"
    }
    puts $csv [join [list $variant $n $lut $ff $dsp $r36 $r18 $tiles \
        [percent $lut 63400] [percent $ff 126800] [percent $dsp 240] \
        [percent $tiles 135] $wns $whs $power $status] ,]
    flush $csv
    catch {close_project}
    cd $root
    puts "=== $variant N=$n status=$status ==="
    return $status
}
proc explore {variant} {
    # Coarse doubling then binary refinement of first observed boundary.
    # Timing need not be monotonic; this estimates the boundary, not proof of a global maximum.
    set low 0
    set high 0
    foreach n {1 2 4 8 16 32 64 128 256 512} {
        set result [trial $variant $n]
        if {$result eq "OK"} {set low $n} else {set high $n; break}
    }
    if {$high == 0} {puts "No failure through N=$low"; return}
    while {$high-$low > 1} {
        set mid [expr {($high+$low)/2}]
        if {[trial $variant $mid] eq "OK"} {set low $mid} else {set high $mid}
    }
    puts "BOUNDARY $variant: highest tested passing N=$low; adjacent failing N=$high"
}
set mode [lindex $argv 0]
if {$mode eq "full"} {
    foreach variant {dsp lut dsp_scratch lut_scratch} {explore $variant}
} elseif {$mode eq "single"} {
    set v [lindex $argv 1]; set n [lindex $argv 2]
    if {$v ni {dsp lut dsp_scratch lut_scratch} || ![string is integer -strict $n] || $n < 1} {close $csv; error "Use single <variant> <positive integer>"}
    trial $v $n
} else {
    foreach variant {dsp lut dsp_scratch lut_scratch} {trial $variant 1}
}
close $csv
puts "Results: $csvpath"
