#===========================================================
# SHA-256 Accelerator Flat RTL - Timing Constraints (SDC)
# Target clock: 667 MHz (1.5ns period)
#===========================================================

#-----------------------------
# Clock definition
#-----------------------------
create_clock -name clk -period 1.500 [get_ports clk]

# Optional but recommended for closure
set_clock_uncertainty 0.050 [get_clocks clk]

#-----------------------------
# Reset: synchronous reset (don't time it)
#-----------------------------
set_false_path -from [get_ports rst]

#-----------------------------
# IO Delays = 20% of period = 0.3ns
#-----------------------------
set_input_delay  0.300 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.300 -clock clk [all_outputs]

#-----------------------------
# DRC / routing friendly constraint
#-----------------------------
set_max_fanout 20 [current_design]

