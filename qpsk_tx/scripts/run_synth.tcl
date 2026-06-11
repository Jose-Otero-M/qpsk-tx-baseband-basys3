# Run synthesis for Vivado project

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize "$script_dir/.."]

source "$script_dir/create_project.tcl"

launch_runs synth_1 -jobs 12
wait_on_run synth_1

open_run synth_1

report_utilization -file "$root_dir/reports/synth_utilization.rpt"
report_timing_summary -file "$root_dir/reports/synth_timing_summary.rpt"

puts "Synthesis completed successfully."