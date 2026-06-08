`ifndef OVIP_AXI_STREAM_MULTIBEAT_TEST__SV
`define OVIP_AXI_STREAM_MULTIBEAT_TEST__SV

// Drives several multi-beat packets through the bus (TLAST is asserted only
// on each packet's final beat). Confirms that:
//   - the transmitter holds TID/TDEST stable across all beats of a packet
//   - the monitor accumulates beats into one trans and publishes once on TLAST
//   - the scoreboard pairs each expected packet with its received counterpart
class ovip_axi_stream_multibeat_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_multibeat_test)

	ovip_axi_stream_scoreboard sb;

	function new(string name = "ovip_axi_stream_multibeat_test", uvm_component parent);
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
		ovip_axi_stream_simple_packet_seq seq = ovip_axi_stream_simple_packet_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.tdata_width  = 4;
		seq.num_packets  = 3;
		seq.lens         = '{2, 5, 8};
		seq.ids          = '{1, 2, 3};
		seq.dests        = '{4, 5, 6};
		seq.sb_ref       = sb;
		seq.start(tx_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
