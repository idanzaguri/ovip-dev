`ifndef OVIP_AXI_MID_TEST_RESET_INFLIGHT_TEST__SV
`define OVIP_AXI_MID_TEST_RESET_INFLIGHT_TEST__SV

// Mid-test reset while a long write AND a long read are simultaneously in
// flight on both channels. Exercises the VIP's ability to drop active state
// on both directions at once and recover for post-reset traffic.
//
// Extra recovery vs. the simple mid_test_reset case: when reset asserts, the
// slave responder sequence is mid-finish_item (its driver was killed), so it
// hangs. We kill it, then restart a fresh slave_seq around the reset pulse.

class ovip_axi_mid_test_reset_inflight_test extends ovip_axi_mid_test_reset_test;

	`uvm_component_utils(ovip_axi_mid_test_reset_inflight_test)

	function new(string name = "ovip_axi_mid_test_reset_inflight_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	task main_phase(uvm_phase phase);
		// NOTE: don't call super.main_phase -- the parent's main_phase runs the
		// simpler pre/post traffic+reset flow; this override replaces it entirely
		// and only reuses the `pulse_reset` / `send_traffic_batch` helpers.
		phase.raise_objection(this);

		// Launch a long write and a long read in parallel. Inter-beat delays on the
		// write stretch the W channel so reset can hit mid-burst on both directions.
		// Pin addr/size for both bursts so the 64-beat transfers stay inside a 4 KiB page.
		// 64 beats x 8 bytes = 512 bytes; write @ 0x0, read @ 0x800 (no overlap, no 4K cross).
		fork
			begin
				ovip_axi_simple_wr_bursts_seq wr = ovip_axi_simple_wr_bursts_seq::type_id::create("wr_long");
				wr.num_trans = 1;
				wr.addr = '{0};
				wr.size = '{OVIP_AXI_SIZE_8B};
				wr.min_burst_len = 64;
				wr.max_burst_len = 64;
				wr.min_delay_between_beats = 2;
				wr.max_delay_between_beats = 4;
				wr.start(master_agent.sqr);
			end
			begin
				ovip_axi_simple_rd_bursts_seq rd = ovip_axi_simple_rd_bursts_seq::type_id::create("rd_long");
				rd.num_trans = 1;
				rd.addr = '{12'h800};
				rd.size = '{OVIP_AXI_SIZE_8B};
				rd.min_burst_len = 64;
				rd.max_burst_len = 64;
				rd.start(master_agent.sqr);
			end
		join_none

		// Let both channels actually become active before pulling the reset.
		repeat(20) @(master_agent.mon.vif.monitor_cb);

		// Pulse reset while both channels are in flight.
		pulse_reset();

		// The pre-reset write/read seqs are now hung in finish_item (their driver
		// was killed by reset). Abandon them.
		disable fork;

		// The slave responder is hung the same way -- kill it and start a fresh one
		// for post-reset traffic.
		slave_seq.kill();
		slave_seq = ovip_axi_base_slave_sequence::type_id::create("slave_seq");
		slave_seq.mem = mem;
		fork slave_seq.start(slave_agent.sqr); join_none

		// Post-reset traffic must complete cleanly -- if the VIP recovered fully,
		// no UVM_ERROR/UVM_FATAL and no INCOMPLETE_*_TRANS at end of test.
		send_traffic_batch("post");

		#100ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_mid_test_reset_inflight_test

`endif
