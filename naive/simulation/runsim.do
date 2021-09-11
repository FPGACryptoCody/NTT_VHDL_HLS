#log the start time
set start_time [clock seconds]

if [file exists work] then {
    vdel -all -lib work
}

vlib work 
vcom -2008 helper_functions.vhd

vcom -2008 pipe.vhd
vcom -2008 adder_2input.vhd
vcom -2008 multiplier.vhd
vcom -2008 barret_reduction.vhd
vcom -2008 ntt_naive_tree.vhd
vcom -2008 tb_ntt_naive_tree.vhd

vsim -novopt -t 1ns -lib work \
     tb_ntt_naive

#log -r *

#do wave.do

view wave
add wave -noupdate -divider {TESTBENCH}
add wave -hex /*
add wave -noupdate -divider {DUT}
add wave -hex /dut/*

#stop simulation when sim_finish is high
#when {/sim_finish = '1'} {
#    echo "Simulation finished normally"
#    set stop_time [clock seconds]
#    set execution_time [expr $stop_time - $start_time]
#    set mins [expr $execution_time / 60]
#    set secs [expr $execution_time - $mins * 60]
#    echo "Total run time is:" $mins "minutes and" $secs "seconds"
#    stop
#}

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

run 400 us
