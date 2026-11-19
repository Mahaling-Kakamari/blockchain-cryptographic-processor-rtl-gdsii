set_db lib_search_path /home/pgvlsi10/Digital/lib
set_db hdl_search_path /home/pgvlsi10/Digital

# Set target library
set_db library /home/pgvlsi10/Digital/lib/slow.lib

# Read HDL files
read_hdl blockchain.v


# Elaborate top-level module
elaborate blockchain

# Read constraints (SDC)
read_sdc blockchain.sdc

# Generic synthesis
syn_generic

# Technology mapping
syn_map

# Optimization
syn_opt

report_timing > block_timing.rpt
report_area > block_area.rpt
report_power > block_power.rpt

write_hdl > block_syn_top.v
write_sdc > block_syn_top.sdc
