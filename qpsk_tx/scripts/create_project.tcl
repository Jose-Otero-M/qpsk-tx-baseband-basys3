# Create Vivado project for Basys 3

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set project_name "qpsk_tx"
set project_dir  "$root_dir/vivado_project"

create_project $project_name $project_dir -part xc7a35ticpg236-1L -force

# Add RTL sources
add_files -fileset sources_1 [glob -nocomplain "$root_dir/rtl/*.v"]
#add_files -fileset sources_1 [glob -nocomplain "$root_dir/rtl/*.sv"]

# Add simulation sources
#add_files -fileset sim_1 [glob -nocomplain "$root_dir/tb/*.v"]
add_files -fileset sim_1 [glob -nocomplain "$root_dir/tb/*.sv"]

# Add constraints
#add_files -fileset constrs_1 [glob -nocomplain "$root_dir/constraints/*.xdc"]

# Set top module
set_property top top_QPSK_baseband_tx [current_fileset]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1