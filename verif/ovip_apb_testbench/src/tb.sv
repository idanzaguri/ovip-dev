`timescale 1ns/1ps

module tb;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_apb_pkg::*;
	import ovip_apb_tests_pkg::*;

	logic pclk, presetn;

	// APB is point-to-point and has no DUT in this testbench. The requester
	// and completer agents share a single interface instance.
	ovip_apb_agent_if apb_if(pclk, presetn);

	initial uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.req_agent*",  "vif", apb_if);
	initial uvm_config_db#(virtual ovip_apb_agent_if)::set(null, "*.comp_agent*", "vif", apb_if);

	`ifdef TEST_NAME // used when running simulation via EDA-Playground
		initial begin
			$dumpfile("dump.vcd"); $dumpvars;
			run_test(`TEST_NAME);
		end
	`else
		initial run_test();
	`endif

	initial
	begin
		$timeformat(-9, 1, "ns");
		pclk    = 1;
		presetn = 1;
		fork forever #500ps pclk = ~pclk; join_none;
		repeat(2) @(posedge pclk);
		presetn = 0;
		repeat(2) @(posedge pclk);
		presetn = 1;
	end

endmodule : tb
