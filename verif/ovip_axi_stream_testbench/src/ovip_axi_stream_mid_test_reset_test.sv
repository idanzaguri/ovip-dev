`ifndef OVIP_AXI_STREAM_MID_TEST_RESET_TEST__SV
`define OVIP_AXI_STREAM_MID_TEST_RESET_TEST__SV

// A reset in the middle of a packet. The transmitter drives TVALID until it
// sees the reset at the next clock edge, as any synchronous transmitter does,
// so the first cycle of the reset may still show TVALID high. From the next
// cycle TVALID must stay low while ARESETn is low. The monitor drops the cut
// packet, and the packets after the release must arrive whole.
class ovip_axi_stream_mid_test_reset_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_mid_test_reset_test)

	ovip_axi_stream_scoreboard sb;

	function new(string name = "ovip_axi_stream_mid_test_reset_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		sb = ovip_axi_stream_scoreboard::type_id::create("sb", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		rx_agent.mon.analysis_port.connect(sb.act_ap);
	endfunction

	task main_phase(uvm_phase phase);
		ovip_axi_stream_simple_packet_seq pre  = ovip_axi_stream_simple_packet_seq::type_id::create("pre");
		ovip_axi_stream_simple_packet_seq post = ovip_axi_stream_simple_packet_seq::type_id::create("post");
		super.main_phase(phase);
		phase.raise_objection(this);

		// one long packet, cut after a few beats; it never completes, so the
		// scoreboard expects nothing of it
		pre.tdata_width = 4;
		pre.num_packets = 1;
		pre.lens        = '{64};
		fork pre.start(tx_agent.master_sqr); join_none
		repeat(4) @(posedge tx_vif.aclk iff (tx_vif.tvalid === 1'b1 && tx_vif.tready === 1'b1));
		#200ps;

		`uvm_info("MID_RST_TEST", "=== mid-test reset asserted mid-packet ===", UVM_LOW)
		disable fork;
		if(!uvm_hdl_force("tb.aresetn", 1'b0))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.aresetn) failed -- adjust the HDL path for your testbench")
		repeat(8) @(posedge tx_vif.aclk);
		tx_agent.master_sqr.stop_sequences();
		if(!uvm_hdl_force("tb.aresetn", 1'b1))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.aresetn) failed")
		repeat(4) @(posedge tx_vif.aclk);
		`uvm_info("MID_RST_TEST", "=== mid-test reset deasserted ===", UVM_LOW)

		// packets after the release, each matched by the scoreboard
		post.tdata_width = 4;
		post.num_packets = 3;
		post.lens        = '{3, 7, 2};
		post.ids         = '{1, 2, 3};
		post.dests       = '{4, 5, 6};
		post.sb_ref      = sb;
		post.start(tx_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
