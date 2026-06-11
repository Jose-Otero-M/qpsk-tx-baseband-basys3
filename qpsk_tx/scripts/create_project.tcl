# Create Vivado project

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

set project_name "qpsk_tx"
set project_dir  "$root_dir/vivado_project"

# Basys 3 FPGA part
create_project $project_name $project_dir -part xc7a35tcpg236-1 -force

# --------------------------------------------------------------------
# Add RTL sources
# --------------------------------------------------------------------

set rtl_files [list]

set rtl_v_files  [glob -nocomplain -directory "$root_dir/rtl" *.v]
set rtl_sv_files [glob -nocomplain -directory "$root_dir/rtl" *.sv]

set rtl_files [concat $rtl_files $rtl_v_files $rtl_sv_files]

if {[llength $rtl_files] > 0} {
    add_files -fileset sources_1 $rtl_files
} else {
    puts "ERROR: No RTL files found in $root_dir/rtl"
    exit 1
}

# --------------------------------------------------------------------
# Add simulation sources
# --------------------------------------------------------------------

set tb_files [list]

set tb_v_files  [glob -nocomplain -directory "$root_dir/tb" *.v]
set tb_sv_files [glob -nocomplain -directory "$root_dir/tb" *.sv]

set tb_files [concat $tb_files $tb_v_files $tb_sv_files]

if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
} else {
    puts "WARNING: No testbench files found in $root_dir/tb"
}

# --------------------------------------------------------------------
# Add constraints
# --------------------------------------------------------------------

set xdc_files [glob -nocomplain -directory "$root_dir/constraints" *.xdc]

if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
} else {
    puts "WARNING: No XDC constraint files found in $root_dir/constraints"
}

# --------------------------------------------------------------------
# Set top module
# --------------------------------------------------------------------

set_property top top_QPSK_baseband_tx [current_fileset]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1