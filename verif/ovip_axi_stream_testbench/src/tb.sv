`timescale 1ns/1ps

module tb;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_stream_pkg::*;
	import ovip_axi_stream_tests_pkg::*;

	logic aclk, aresetn;

	// AXI-Stream is point-to-point and has no DUT in this testbench. The
	// transmitter and receiver agents share a single interface instance.
	ovip_axi_stream_agent_if axis_if(aclk, aresetn);

	initial uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.tx_agent*", "vif", axis_if);
	initial uvm_config_db#(virtual ovip_axi_stream_agent_if)::set(null, "*.rx_agent*", "vif", axis_if);

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
		aclk    = 1;
		aresetn = 1;
		fork forever #500ps aclk = ~aclk; join_none;
		repeat(2) @(posedge aclk);
		aresetn = 0;
		repeat(2) @(posedge aclk);
		aresetn = 1;
	end

endmodule : tb
