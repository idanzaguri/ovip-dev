`include "uvm_macros.svh"

package ovip_axi_stream_tests_pkg;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_stream_pkg::*;

	`include "ovip_axi_stream_expected_errors_report_server.sv"
	`include "ovip_axi_stream_base_test.sv"
	`include "ovip_axi_stream_smoke_test.sv"
	`include "ovip_axi_stream_multibeat_test.sv"
	`include "ovip_axi_stream_backpressure_test.sv"
	`include "ovip_axi_stream_reserved_byte_qual_test.sv"
endpackage : ovip_axi_stream_tests_pkg
