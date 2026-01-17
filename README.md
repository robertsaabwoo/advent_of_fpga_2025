Hello !

My name is Robert, and this is my submission to the Advent of FPGA 2025! The meat of this repository is the Hardcaml 
solution to day 12, which uses a pseudo recursive algorithm to be able to solve the problem with minimal hardware usage. In fact, 
I was able to take the verilog code generated from the hardcaml file and create a tiny tapeout of the program (tiny tapeout here:
https://github.com/robertsaabwoo/advent_of_fpga_2025_day_12_tiny_tapeout). 

The pseudo recursion works by storing a single copy of the actual map in memory / registers (tiny tapeout is not as great with its 
current memory support, but in an FPGA URAM or BRAM would work quite well with this), and keeping track of all shapes and orientations
that were placed in one of the many attempts to fit all the gifts into a single box. If it fails, the code is able to back track and try 
a new orientation without the need for large stacks as a CPU would. 

Furthermore, this implementation shows a lot of promise for parallelization,
which was not emphasized in this design as it is meant for tiny tapeout, but with 
an FPGA would help accelarate and further pipeline (as this design is already pipelined in how it retrieves and writes values from memory).

I had a lot of fun learning how Jane Street's Hardcaml works, and if I could give any feedback I would say that having the verilog variable names be 
extensions of the original hardcaml variable names as opposed to a long list of numbers would make the verilog much more readable when debugging how the
Hardcaml compiler interpeted my HDL. I think Vivado's HLS tools provide a good example of this as they can normally point to the netlist or interface that
relate to the generated verilog.

I have also included the original system verilog codes that were made for day 3 and day 12 when I was first starting the project, however the HardCaml and Tiny Tapeout
are the meat of this.
