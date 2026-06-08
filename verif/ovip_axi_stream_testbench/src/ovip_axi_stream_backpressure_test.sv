`ifndef OVIP_AXI_STREAM_BACKPRESSURE_TEST__SV
`define OVIP_AXI_STREAM_BACKPRESSURE_TEST__SV

// Reconfigures the receiver-side TREADY pattern to a noisy alternating
// profile (3 cycles low, 1 cycle high, repeating) and runs the multi-beat
// sequence through it. The packets still round-trip; the only difference is
// the wire takes longer because the receiver is busy sometimes.
class ovip_axi_stream_backpressure_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_backpressure_test)

	ovip_axi_stream_scoreboard sb;

	function new(string name = "ovip_axi_stream_backpressure_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		// Apply a noisy TREADY default before the agent picks it up.
		rx_cfg.default_tready_pattern = '{cycles:'{3, 1}, loop:1};
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
		seq.tdata_width = 4;
		seq.num_packets = 3;
		seq.lens        = '{2, 5, 4};
		seq.ids         = '{7, 8, 9};
		seq.sb_ref      = sb;
		seq.start(tx_agent.master_sqr);
		#400ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
