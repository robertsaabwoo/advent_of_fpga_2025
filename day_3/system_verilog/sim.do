if {[file exists work]} {
    vdel -all
}
vlib work

# Compile sources
vlog -sv axi_stream_if.sv
vlog -sv day_3.sv
vlog -sv day_3_tb.sv

# Simulate in console mode
vsim -c work.day_3_tb
run -all
quit -f
