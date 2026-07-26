`include "uvm_macros.svh"

package ovip_apb_tests_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_apb_pkg::*;

	`include "ovip_apb_expected_errors_report_server.sv"
	`include "ovip_apb_base_test.sv"
	`include "ovip_apb_smoke_test.sv"
	`include "ovip_apb_wait_states_test.sv"
	`include "ovip_apb_error_response_test.sv"
	`include "ovip_apb_strobe_test.sv"
endpackage : ovip_apb_tests_pkg
