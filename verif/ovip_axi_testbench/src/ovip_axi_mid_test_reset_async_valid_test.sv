`ifndef OVIP_AXI_MID_TEST_RESET_ASYNC_VALID_TEST__SV
`define OVIP_AXI_MID_TEST_RESET_ASYNC_VALID_TEST__SV

// A reset while an R beat waits for RREADY, from a slave that drops RVALID
// with the reset, as an asynchronously reset one does (a NoC's NI). The
// master's monitor must take the reset as the end of the beat, not as a
// VALID dropped before its handshake, and traffic after the release must
// run clean. Which of the stability thread and rst_monitor wakes first on
// that edge is the simulator's choice, so the test guards the path but may
// pass on a monitor without the reset check too.
class ovip_axi_mid_test_reset_async_valid_test extends ovip_axi_mid_test_reset_test;

	`uvm_component_utils(ovip_axi_mid_test_reset_async_valid_test)

	function new(string name = "ovip_axi_mid_test_reset_async_valid_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	task main_phase(uvm_phase phase);
		virtual ovip_axi_agent_if    vif = master_agent.mon.vif;
		ovip_axi_bytestream_sequence rd  = ovip_axi_bytestream_sequence::type_id::create("rd_long");
		phase.raise_objection(this);

		// a long read whose master holds RREADY low 3 cycles in 4
		rd.tr_type        = OVIP_AXI_READ_TRANS;
		rd.addr           = 12'h800;
		rd.size           = OVIP_AXI_SIZE_8B;
		rd.read_size      = 512;
		rd.rready_pattern = '{cycles:'{3, 1}, loop:1};
		fork rd.start(master_agent.sqr); join_none
		@(vif.monitor_cb iff (vif.monitor_cb.rvalid && !vif.monitor_cb.rready));
		#200ps;

		// the reset, and RVALID dropping with it
		`uvm_info("MID_RST_TEST", "=== mid-test reset asserted, RVALID dropped with it ===", UVM_LOW)
		disable fork;
		if(!uvm_hdl_force("tb.rst_n", 1'b0) || !uvm_hdl_force("tb.rvalid", 1'b0))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force failed -- adjust the HDL paths for your testbench")
		repeat(4) @(vif.monitor_cb);
		if(!uvm_hdl_release("tb.rvalid"))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_release(tb.rvalid) failed")
		repeat(6) @(vif.monitor_cb);
		if(!uvm_hdl_force("tb.rst_n", 1'b1))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.rst_n) failed")
		@(vif.monitor_cb iff vif.monitor_cb.aresetn);
		repeat(4) @(vif.monitor_cb);
		`uvm_info("MID_RST_TEST", "=== mid-test reset deasserted ===", UVM_LOW)

		// the responder anew (its driver dropped the item it was finishing),
		// then traffic after the release
		slave_seq.kill();
		slave_seq = ovip_axi_base_slave_sequence::type_id::create("slave_seq");
		slave_seq.mem = mem;
		fork slave_seq.start(slave_agent.sqr); join_none
		send_traffic_batch("post");
		#100ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_mid_test_reset_async_valid_test

`endif
