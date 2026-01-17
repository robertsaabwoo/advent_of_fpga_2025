if {[file exists work]} {
    vdel -all
}
vlib work

# Compile sources
vlog -sv axi_stream_if.sv
vlog -sv day_12.sv
vlog -sv day_12_tb.sv

# Simulate in console mode
vsim -c work.day_12_tb
run -all
quit -f
