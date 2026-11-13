
# Timing constraints for the 16-bit ALU
current_design alu16

# Clock: 20 ns = 50 MHz
create_clock -name clk -period 20.000 [get_ports clk]

# Clock quality assumptions
set_clock_transition 0.150 [get_clocks clk]
set_clock_uncertainty 0.250 [get_clocks clk]

# External input arrival times (assumption: 4 ns)
set_input_delay 4.000 -clock clk [get_ports {A[*]}]
set_input_delay 4.000 -clock clk [get_ports {B[*]}]
set_input_delay 4.000 -clock clk [get_ports {opcode[*]}]

# External output requirements (assumption: 4 ns)
set_output_delay 4.000 -clock clk [get_ports {Y[*]}]
set_output_delay 4.000 -clock clk [get_ports {Z N C V}]

# Output load assumptions (pF)
set_load -pin_load 0.0334 [get_ports {Y[*]}]
set_load -pin_load 0.0334 [get_ports {Z N C V}]

# Model the external drivers of data inputs.
# Do not assign an external data-driver model to the clock.
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 \
    -pin Y [get_ports {A[*]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 \
    -pin Y [get_ports {B[*]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 \
    -pin Y [get_ports {opcode[*]}]

# Electrical design-rule limits
set_max_transition 0.750 [current_design]
set_max_capacitance 0.200 [current_design]
set_max_fanout 10 [current_design]
