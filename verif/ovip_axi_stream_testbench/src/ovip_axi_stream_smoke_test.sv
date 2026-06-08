`ifndef OVIP_AXI_STREAM_SMOKE_TEST__SV
`define OVIP_AXI_STREAM_SMOKE_TEST__SV

// Smallest end-to-end check: build 4 single-beat packets at the transmitter,
// drive them onto the shared interface, let both monitors (TX and RX) sample
// them, push the TX monitor's published trans as "expected" into the
// scoreboard and the RX monitor's published trans as "actual". Pass = both
// sides see the same packets, scoreboard reports matched=4.
class ovip_axi_stream_smoke_seq extends ovip_axi_stream_base_master_sequence;
	`uvm_object_utils(ovip_axi_stream_smoke_seq)

	// Set by the test before start(). When non-null, the sequence stages an
	// expected snapshot of each packet into the scoreboard before driving it,
	// which keeps the expected/actual queue order deterministic without
	// needing a separate predictor component.
	ovip_axi_stream_scoreboard sb_ref;
	int num_packets = 4;

	function new(string name = "ovip_axi_stream_smoke_seq");
		super.new(name);
	endfunction

	virtual task body();
		for(int ii = 0; ii < num_packets; ii++)
		begin
			ovip_axi_stream_trans tr  = ovip_axi_stream_trans::type_id::create($sformatf("tr_%0d", ii));
			ovip_axi_stream_trans exp = ovip_axi_stream_trans::type_id::create($sformatf("exp_%0d", ii));
			tr.id   = ii;
			tr.dest = 0;
			tr.data_beats = '{32'hC0DE_0000 | ii};
			tr.keep_beats = '{4'hF};
			tr.strb_beats = '{4'hF};
			exp.copy(tr);
			if(sb_ref != null) sb_ref.exp_ap.write(exp);
			send(tr);
		end
	endtask
endclass


class ovip_axi_stream_smoke_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_smoke_test)

	ovip_axi_stream_scoreboard sb;

	function new(string name = "ovip_axi_stream_smoke_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		sb = ovip_axi_stream_scoreboard::type_id::create("sb", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		// Only the receiver-side monitor feeds the actual port -- the
		// sequence pushes the expected side directly through `sb_ref`.
		rx_agent.mon.analysis_port.connect(sb.act_ap);
	endfunction

	task main_phase(uvm_phase phase);
		ovip_axi_stream_smoke_seq seq = ovip_axi_stream_smoke_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.sb_ref = sb;
		seq.start(tx_agent.master_sqr);
		#200ns; // settle window so the last beat's analysis_port writes land before final_phase
		phase.drop_objection(this);
	endtask
endclass

`endif
