// Per-beat RRESP. The slave answers beat 1 of every multi-beat read with
// SLVERR and the other beats OKAY. The item the master sequence gets back must
// carry the beat in resp_beats, `resp` must be the worst (SLVERR), and the
// monitor's item must agree. A single-beat read stays all OKAY.

class ovip_axi_rresp_per_beat_slave_seq extends ovip_axi_base_slave_sequence;
	int err_beat = 1;
	`uvm_object_utils(ovip_axi_rresp_per_beat_slave_seq)

	function new(string name = "ovip_axi_rresp_per_beat_slave_seq");
		super.new(name);
	endfunction

	virtual function ovip_axi_resp_t get_response_code(ovip_axi_trans tr);
		if(tr.tr_type == OVIP_AXI_READ_TRANS && tr.len >= err_beat)
		begin
			tr.resp_beats.delete();
			for(int ii = 0; ii <= tr.len; ii++)
				tr.resp_beats.push_back((ii == err_beat) ? OVIP_AXI_RESP_SLVERR : OVIP_AXI_RESP_OKAY);
			return OVIP_AXI_RESP_SLVERR;
		end
		return OVIP_AXI_RESP_OKAY;
	endfunction : get_response_code
endclass : ovip_axi_rresp_per_beat_slave_seq


class ovip_axi_rresp_per_beat_sub extends uvm_subscriber #(ovip_axi_trans);
	ovip_axi_trans reads[$];
	`uvm_component_utils(ovip_axi_rresp_per_beat_sub)

	function new(string name = "ovip_axi_rresp_per_beat_sub", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	function void write(ovip_axi_trans t);
		if(t.tr_type == OVIP_AXI_READ_TRANS) reads.push_back(t);
	endfunction
endclass : ovip_axi_rresp_per_beat_sub


class ovip_axi_rresp_per_beat_test extends ovip_axi_base_test;
	ovip_axi_rresp_per_beat_sub m_sub;
	`uvm_component_utils(ovip_axi_rresp_per_beat_test)

	function new(string name = "ovip_axi_rresp_per_beat_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(), ovip_axi_rresp_per_beat_slave_seq::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		m_sub = ovip_axi_rresp_per_beat_sub::type_id::create("m_sub", this);
	endfunction : build_phase

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		master_agent.mon.analysis_port.connect(m_sub.analysis_export);
	endfunction : connect_phase

	// Every beat of `tr` against the expected list, on the item named `who`.
	function void check_beats(string who, ovip_axi_trans tr, ovip_axi_resp_t expect_beats[$], ovip_axi_resp_t expect_resp);
		if(tr.resp_beats.size() != expect_beats.size())
			`uvm_error("RRESP", $sformatf("%s %s: resp_beats has %0d entries, expected %0d", who, tr.convert2string(), tr.resp_beats.size(), expect_beats.size()))
		else
			foreach(expect_beats[ii])
				if(tr.resp_beats[ii] != expect_beats[ii])
					`uvm_error("RRESP", $sformatf("%s %s: beat %0d is %s, expected %s", who, tr.convert2string(), ii, tr.resp_beats[ii].name(), expect_beats[ii].name()))
		if(tr.resp != expect_resp)
			`uvm_error("RRESP", $sformatf("%s %s: resp is %s, expected the worst beat, %s", who, tr.convert2string(), tr.resp.name(), expect_resp.name()))
	endfunction : check_beats

	task main_phase(uvm_phase phase);
		ovip_axi_resp_t mixed[$]  = '{OVIP_AXI_RESP_OKAY, OVIP_AXI_RESP_SLVERR, OVIP_AXI_RESP_OKAY, OVIP_AXI_RESP_OKAY};
		ovip_axi_resp_t single[$] = '{OVIP_AXI_RESP_OKAY};
		ovip_axi_simple_rd_bursts_seq seq4, seq1;
		super.main_phase(phase);
		phase.raise_objection(this);

		// three 4-beat reads: beat 1 of each answers SLVERR
		seq4 = ovip_axi_simple_rd_bursts_seq::type_id::create("seq4");
		seq4.num_trans = 3;
		seq4.min_burst_len = 3;
		seq4.max_burst_len = 3;
		seq4.start(master_agent.sqr);
		foreach(seq4.tr_pool[ii]) check_beats("master item", seq4.tr_pool[ii], mixed, OVIP_AXI_RESP_SLVERR);

		// a single-beat read: all OKAY
		seq1 = ovip_axi_simple_rd_bursts_seq::type_id::create("seq1");
		seq1.num_trans = 1;
		seq1.start(master_agent.sqr);
		check_beats("master item", seq1.tr_pool[0], single, OVIP_AXI_RESP_OKAY);

		// the monitor saw the same four reads, with the same per-beat answers
		repeat(4) @(master_vif.monitor_cb);
		if(m_sub.reads.size() != 4)
			`uvm_error("RRESP", $sformatf("the monitor reported %0d reads, expected 4", m_sub.reads.size()))
		else
		begin
			for(int ii = 0; ii < 3; ii++) check_beats("monitor item", m_sub.reads[ii], mixed, OVIP_AXI_RESP_SLVERR);
			check_beats("monitor item", m_sub.reads[3], single, OVIP_AXI_RESP_OKAY);
		end
		`uvm_info("RRESP", "per-beat RRESP: 3 mixed reads + 1 single-beat read checked on the master item and the monitor item", UVM_LOW)

		phase.drop_objection(this);
	endtask : main_phase
endclass : ovip_axi_rresp_per_beat_test
