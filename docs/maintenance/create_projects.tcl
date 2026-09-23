set root [file normalize [file join [file dirname [info script]] ../..]]
foreach name {adda/project/ce_fft_adda.xpr tb/ce_fft_tb.xpr} {
 if {[file exists $root/$name]} {error "Project exists: $name. Open the existing XPR instead."}
}
set part xczu47dr-ffve1156-2-i
create_project ce_fft_adda $root/adda/project -part $part
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
add_files [glob $root/rtl/*.sv]
add_files [glob $root/rtl/*.v]
add_files $root/rtl/ce_config.vh
set_property include_dirs $root/rtl [get_filesets sources_1]
add_files $root/rtl/hmc7044_module.edf
add_files [glob $root/coeff/*.mem]
foreach name {ce_fft_ip ila_adc fifo_generator_0} {add_files $root/ip/$name/$name.xci}
add_files $root/adda/bd/design_1/design_1.bd
open_bd_design $root/adda/bd/design_1/design_1.bd
validate_bd_design
generate_target all [get_files design_1.bd]
set wrappers [make_wrapper -files [get_files design_1.bd] -top]
file copy [lindex $wrappers 0] $root/adda/design_1_wrapper.v
add_files $root/adda/design_1_wrapper.v
add_files -fileset constrs_1 [glob $root/adda/constraints/*.xdc]
set_property top sys_top [get_filesets sources_1]
set_property generic DATA_WIDTH=28 [get_filesets sources_1]
update_compile_order -fileset sources_1
report_ip_status -file $root/docs/adda_ip_status.txt
close_project
create_project ce_fft_tb $root/tb -part $part
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
foreach name {ce_complex_gain.sv ce_fft_core.sv ce_fft_engine.sv ce_fft_ols_top.sv adda_fft_path.sv ce_async_fifo.sv ce_coeff_control.sv} {add_files $root/rtl/$name}
add_files $root/rtl/ce_config.vh
set_property include_dirs $root/rtl [get_filesets sources_1]
set_property include_dirs $root/rtl [get_filesets sim_1]
add_files [glob $root/coeff/*.mem]
add_files $root/ip/ce_fft_ip/ce_fft_ip.xci
generate_target simulation [get_ips ce_fft_ip]
add_files -fileset sim_1 $root/tb/tb_main.sv
set_property top adda_fft_path [get_filesets sources_1]
set_property top tb_main [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
set_property -dict [list xsim.simulate.xsim.more_options "-testplusarg INPUT_DIR=$root/data/input -testplusarg OUTPUT_DIR=$root/data/output"] [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
puts PROJECTS_READY
