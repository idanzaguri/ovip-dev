`ifndef OVIP_AXI_STREAM_MID_TEST_RESET_GAP_TEST__SV
`define OVIP_AXI_STREAM_MID_TEST_RESET_GAP_TEST__SV

// Counts the packets a monitor publishes.
class ovip_axi_stream_packet_counter extends uvm_subscriber#(ovip_axi_stream_trans);
	`uvm_component_utils(ovip_axi_stream_packet_counter)
	int n;

	function new(string name = "ovip_axi_stream_packet_counter", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void write(ovip_axi_stream_trans t);
		n++;
	endfunction
endclass : ovip_axi_stream_packet_counter


// The packet sequence with a fixed gap after every packet.
class ovip_axi_stream_gap_packet_seq extends ovip_axi_stream_simple_packet_seq;
	`uvm_object_utils(ovip_axi_stream_gap_packet_seq)
	int unsigned gap = 0;   // delay_until_next_trans of every packet

	function new(string name = "ovip_axi_stream_gap_packet_seq");
		super.new(name);
	endfunction

	virtual task send(ovip_axi_stream_trans tr);
		tr.delay_until_next_trans = gap;
		super.send(tr);
	endtask
endclass : ovip_axi_stream_gap_packet_seq


// Two resets, and after each release no packet from before it may appear.
//   1. A reset in the transmitter's gap after a packet. The driver still holds
//      that packet, done, while it waits out the gap; it must drop it, not send
//      it again after the release.
//   2. A reset while a beat waits for TREADY, with TVALID dropped with it, as
//      an asynchronously reset transmitter does (a NoC's NI). The monitors must
//      take the reset as the end of the beat. Which of the stability thread and
//      rst_monitor wakes first on that edge is the simulator's choice, so this
//      part guards the path but may pass without the monitor's reset check.
// After each release, the receiver's monitor must publish nothing until new
// packets are sent, and then exactly those.
class ovip_axi_stream_mid_test_reset_gap_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_mid_test_reset_gap_test)

	ovip_axi_stream_packet_counter rx_count;

	function new(string name = "ovip_axi_stream_mid_test_reset_gap_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		rx_count = ovip_axi_stream_packet_counter::type_id::create("rx_count", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		rx_agent.mon.analysis_port.connect(rx_count.analysis_export);
	endfunction

	// the reset held 8 cycles; `drop_tvalid` drops TVALID with it. The
	// sequencer drops the stopped sequences once the driver has seen the reset
	task pulse_reset(bit drop_tvalid);
		if(!uvm_hdl_force("tb.aresetn", 1'b0) || (drop_tvalid && !uvm_hdl_force("tb.axis_if.tvalid", 1'b0)))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force failed -- adjust the HDL paths for your testbench")
		repeat(4) @(posedge tx_vif.aclk);
		if(drop_tvalid && !uvm_hdl_release("tb.axis_if.tvalid"))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_release(tb.axis_if.tvalid) failed")
		tx_agent.master_sqr.stop_sequences();
		repeat(4) @(posedge tx_vif.aclk);
		if(!uvm_hdl_force("tb.aresetn", 1'b1))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.aresetn) failed")
	endtask

	// no packet for 60 cycles after the release, then n new ones, all arriving
	task after_release(string what, int n);
		ovip_axi_stream_simple_packet_seq post = ovip_axi_stream_simple_packet_seq::type_id::create("post");
		int n0 = rx_count.n;   // the packets so far
		repeat(60) @(posedge tx_vif.aclk);
		if(rx_count.n != n0)
			`uvm_error("MID_RST_TEST", $sformatf("%s: %0d packet(s) arrived after the release with no sequence running: sent from before the reset", what, rx_count.n - n0))
		post.tdata_width = 4;
		post.num_packets = n;
		post.lens        = '{3, 2, 4};
		post.start(tx_agent.master_sqr);
		repeat(20) @(posedge tx_vif.aclk);
		if(rx_count.n != n0 + n)
			`uvm_error("MID_RST_TEST", $sformatf("%s: %0d packet(s) arrived after the release, %0d sent", what, rx_count.n - n0, n))
		else
			`uvm_info("MID_RST_TEST", $sformatf("%s: nothing from before the reset, and the %0d new packet(s) arrived", what, n), UVM_LOW)
	endtask

	task main_phase(uvm_phase phase);
		ovip_axi_stream_gap_packet_seq gap_seq = ovip_axi_stream_gap_packet_seq::type_id::create("gap_seq");
		ovip_axi_stream_simple_packet_seq stall_seq = ovip_axi_stream_simple_packet_seq::type_id::create("stall_seq");
		super.main_phase(phase);
		phase.raise_objection(this);

		// 1. the reset in the gap after a packet
		gap_seq.tdata_width = 4;
		gap_seq.num_packets = 2;
		gap_seq.lens        = '{3, 3};
		gap_seq.gap         = 30;
		fork gap_seq.start(tx_agent.master_sqr); join_none
		@(posedge tx_vif.aclk iff (tx_vif.tvalid === 1'b1 && tx_vif.tready === 1'b1 && tx_vif.tlast === 1'b1));
		repeat(5) @(posedge tx_vif.aclk);
		#200ps;
		`uvm_info("MID_RST_TEST", "=== reset in the gap after a packet ===", UVM_LOW)
		disable fork;
		pulse_reset(0);
		after_release("the reset in the gap", 3);

		// 2. the reset while a beat waits for TREADY, TVALID dropped with it
		rx_agent.slave_drv.put_tready_pattern('{6, 1}, 1);
		stall_seq.tdata_width = 4;
		stall_seq.num_packets = 1;
		stall_seq.lens        = '{8};
		fork stall_seq.start(tx_agent.master_sqr); join_none
		@(posedge tx_vif.aclk iff (tx_vif.tvalid === 1'b1 && tx_vif.tready === 1'b0));
		#200ps;
		`uvm_info("MID_RST_TEST", "=== reset under a waiting beat, TVALID dropped with it ===", UVM_LOW)
		disable fork;
		pulse_reset(1);
		rx_agent.slave_drv.put_tready_pattern('{0, 1}, 0);
		after_release("the reset under a waiting beat", 2);

		#100ns;
		phase.drop_objection(this);
	endtask
endclass : ovip_axi_stream_mid_test_reset_gap_test

`endif
