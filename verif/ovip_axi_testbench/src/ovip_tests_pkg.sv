`include "uvm_macros.svh"

package ovip_tests_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;

	`include "ovip_mem_test.sv"

	`include "ovip_axi_expected_errors_report_server.sv"
	`include "ovip_axi_base_test.sv"

	`include "ovip_axi3_wr_ooo_and_interleaving_test.sv"
	`include "ovip_axi_bresp_ooo_test.sv"
	`include "ovip_axi_auto_byte_lanes_alignment_test.sv"
	`include "ovip_axi_rd_ooo_and_interleaving_test.sv"
	`include "ovip_axi_b2b_test.sv"
	`include "ovip_axi_data_before_address_test.sv"
	`include "ovip_axi_narrow_transfer_alignment_test.sv"
	`include "ovip_axi_bad_dba_test.sv"
	`include "ovip_axi_xz_test.sv"
	`include "ovip_axi_signal_stability_test.sv"
	`include "ovip_axi_4lite_test.sv"
	`include "ovip_axi_data_integrity_test.sv"
	`include "ovip_axi_burst_type_test.sv"
	`include "ovip_axi_fixed_full_width_alignment_test.sv"
	`include "ovip_axi_wrap_burst_test.sv"

	`include "ovip_axi_simple_timing_test.sv"
	`include "ovip_axi_aux_signals_test.sv"
	`include "ovip_axi_mid_test_reset_test.sv"
	`include "ovip_axi_mid_test_reset_inflight_test.sv"
endpackage : ovip_tests_pkg
