`ifndef OVIP_AXI_STREAM_RESERVED_BYTE_QUAL_TEST__SV
`define OVIP_AXI_STREAM_RESERVED_BYTE_QUAL_TEST__SV

// Negative test: drive a single packet where one byte has the reserved
// TKEEP=0, TSTRB=1 combination (spec section 2.5.3). The monitor must raise
// AXIS_MON/BYTE_QUAL on the receiver side; the test absorbs that error via
// expected_errors so the run still reports SvtTestEpilog: Passed.

class ovip_axi_stream_reserved_byte_qual_seq extends ovip_axi_stream_base_master_sequence;
	`uvm_object_utils(ovip_axi_stream_reserved_byte_qual_seq)
	function new(string name = "ovip_axi_stream_reserved_byte_qual_seq");
		super.new(name);
	endfunction
	virtual task body();
		ovip_axi_stream_trans tr = ovip_axi_stream_trans::type_id::create("bad_tr");
		tr.id   = 0;
		tr.dest = 0;
		// Byte 0: data (keep=1, strb=1). Byte 1: reserved (keep=0, strb=1).
		// Byte 2-3: marked as null (both qualifiers zero).
		tr.data_beats = '{32'h0000_BEEF};
		tr.keep_beats = '{4'b0001};
		tr.strb_beats = '{4'b0011};
		send(tr);
	endtask
endclass


class ovip_axi_stream_reserved_byte_qual_test extends ovip_axi_stream_base_test;
	`uvm_component_utils(ovip_axi_stream_reserved_byte_qual_test)

	function new(string name = "ovip_axi_stream_reserved_byte_qual_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	task main_phase(uvm_phase phase);
		ovip_axi_stream_reserved_byte_qual_seq seq;
		super.main_phase(phase);
		phase.raise_objection(this);

		// Both the TX-side and RX-side monitors fire the reserved-combo error
		// on the same beat, so we register the regex twice.
		custom_report_server.in_order = 0;
		custom_report_server.expected_errors.push_back("reserved TKEEP=0 TSTRB=1 combination");
		custom_report_server.expected_errors.push_back("reserved TKEEP=0 TSTRB=1 combination");

		seq = ovip_axi_stream_reserved_byte_qual_seq::type_id::create("seq");
		seq.start(tx_agent.master_sqr);

		#100ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
