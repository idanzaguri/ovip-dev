`ifndef OVIP_AXI_MID_TEST_RESET_TEST__SV
`define OVIP_AXI_MID_TEST_RESET_TEST__SV

// Mid-test reset test: verifies that asserting/deasserting `aresetn` mid-run
// clears all VIP state cleanly and the VIP is fully functional afterwards.
// Pass criterion is the base test's UVM_ERROR/UVM_FATAL == 0 sweep.

class ovip_axi_mid_test_reset_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_mid_test_reset_test)

	function new(string name = "ovip_axi_mid_test_reset_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_8B;
	endfunction : build_phase

	// Drive a small batch of write+read traffic through the master and let it complete.
	// Addresses/sizes are pinned so the bursts (max 4 beats x 4B = 16B) never cross a
	// 4 KiB page regardless of seed -- this test cares about reset behavior, not stimulus.
	task send_traffic_batch(string tag);
		ovip_axi_simple_wr_bursts_seq wr = ovip_axi_simple_wr_bursts_seq::type_id::create($sformatf("wr_%s", tag));
		ovip_axi_simple_rd_bursts_seq rd = ovip_axi_simple_rd_bursts_seq::type_id::create($sformatf("rd_%s", tag));
		`uvm_info("MID_RST_TEST", $sformatf("--- %s: sending traffic ---", tag), UVM_LOW)
		wr.num_trans = 3;
		wr.addr = '{0, 256, 512};
		wr.size = '{OVIP_AXI_SIZE_4B, OVIP_AXI_SIZE_4B, OVIP_AXI_SIZE_4B};
		wr.min_burst_len = 0; wr.max_burst_len = 3;
		wr.start(master_agent.sqr);
		rd.num_trans = 3;
		rd.addr = '{12'h800, 12'h900, 12'hA00};
		rd.size = '{OVIP_AXI_SIZE_4B, OVIP_AXI_SIZE_4B, OVIP_AXI_SIZE_4B};
		rd.min_burst_len = 0; rd.max_burst_len = 3;
		rd.start(master_agent.sqr);
	endtask : send_traffic_batch

	// Pulse the testbench reset (mid-test) and wait for it to deassert again.
	// Uses uvm_hdl_force/uvm_hdl_release so we don't compile-depend on the tb hierarchy.
	task pulse_reset();
		`uvm_info("MID_RST_TEST", "=== mid-test reset asserted ===", UVM_LOW)
		if(!uvm_hdl_force("tb.rst_n", 1'b0))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.rst_n) failed -- adjust the HDL path for your testbench")
		repeat(10) @(master_agent.mon.vif.monitor_cb);
		if(!uvm_hdl_force("tb.rst_n", 1'b1))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.rst_n) failed -- adjust the HDL path for your testbench")
		@(master_agent.mon.vif.monitor_cb iff master_agent.mon.vif.monitor_cb.aresetn);
		repeat(4) @(master_agent.mon.vif.monitor_cb);
		`uvm_info("MID_RST_TEST", "=== mid-test reset deasserted ===", UVM_LOW)
	endtask : pulse_reset

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		// Phase A: pre-reset traffic completes normally.
		send_traffic_batch("preA");

		// Mid-test reset: every VIP component must drop in-flight state and re-arm.
		pulse_reset();

		// Phase B: post-reset traffic must complete cleanly with no leftover state
		// (no OUTSTANDING_EXCEED, no INCOMPLETE_*_TRANS at end of test, etc.).
		send_traffic_batch("postB");

		#100ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_mid_test_reset_test

`endif
