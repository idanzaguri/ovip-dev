// The slave answers SLVERR outside its memory's valid ranges. The memory
// owns 2 KiB at 0; a write and a read inside are OKAY and the data round
// trips; a write and a read outside, and a write that runs past the end,
// come back SLVERR with the memory untouched and a read of zeros. The report
// SLAVE_SEQ/OUT_OF_RANGE fires once per refused request when the knob is on.

class ovip_axi_slave_out_of_range_test extends ovip_axi_base_test;
	`uvm_component_utils(ovip_axi_slave_out_of_range_test)

	function new(string name = "ovip_axi_slave_out_of_range_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		mem.add_valid_range('h0, 'h800);           // the slave owns [0, 0x800)
		slave_seq.wr_mem_update_on_bresp = 0;      // commit at WLAST, so the read-back right after B sees the data
	endfunction : build_phase

	task write_burst(ovip_axi_addr_t addr, int len, output ovip_axi_trans tr);
		ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("wr");
		seq.num_trans = 1; seq.min_burst_len = len; seq.max_burst_len = len;
		seq.addr.push_back(addr);
		seq.size.push_back(OVIP_AXI_SIZE_8B);        // full-width beats, so the read-back compares beat for beat
		seq.start(master_agent.sqr);
		tr = seq.tr_pool[0];
	endtask

	task read_burst(ovip_axi_addr_t addr, int len, output ovip_axi_trans tr);
		ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("rd");
		seq.num_trans = 1; seq.min_burst_len = len; seq.max_burst_len = len;
		seq.addr.push_back(addr);
		seq.size.push_back(OVIP_AXI_SIZE_8B);
		seq.start(master_agent.sqr);
		tr = seq.tr_pool[0];
	endtask

	task main_phase(uvm_phase phase);
		ovip_axi_trans wr, rd;
		ovip_mem_space_catcher catcher = new("range", "SLAVE_SEQ/OUT_OF_RANGE");
		super.main_phase(phase);
		phase.raise_objection(this);
		slave_seq.report_out_of_range = 0;           // this test aims outside on purpose

		// inside: a 4-beat write, then its read-back
		write_burst('h100, 3, wr);
		if(wr.resp != OVIP_AXI_RESP_OKAY) `uvm_error("RANGE", $sformatf("write inside the range answered %s", wr.resp.name()))
		read_burst('h100, 3, rd);
		if(rd.resp != OVIP_AXI_RESP_OKAY) `uvm_error("RANGE", $sformatf("read inside the range answered %s", rd.resp.name()))
		else
			// the write sequence randomizes the strobes, so only the strobed bytes land
			foreach(wr.data_beats[ii])
				for(int b = 0; b < 8; b++)
					if(wr.strb_beats[ii][b] && rd.data_beats[ii][b*8 +: 8] != wr.data_beats[ii][b*8 +: 8])
						`uvm_error("RANGE", $sformatf("read-back inside the range: beat %0d byte %0d is 0x%02h, wrote 0x%02h", ii, b, rd.data_beats[ii][b*8 +: 8], wr.data_beats[ii][b*8 +: 8]))

		// outside: a write, then a read, both refused and the memory untouched
		write_burst('h2000, 3, wr);
		if(wr.resp != OVIP_AXI_RESP_SLVERR) `uvm_error("RANGE", $sformatf("write outside the range answered %s, expected SLVERR", wr.resp.name()))
		if(mem.line_exists('h2000)) `uvm_error("RANGE", "the refused write touched the memory")
		read_burst('h2000, 3, rd);
		if(rd.resp != OVIP_AXI_RESP_SLVERR) `uvm_error("RANGE", $sformatf("read outside the range answered %s, expected SLVERR", rd.resp.name()))
		foreach(rd.data_beats[ii]) if(rd.data_beats[ii] != 0) `uvm_error("RANGE", "the refused read returned data")
		foreach(rd.resp_beats[ii]) if(rd.resp_beats[ii] != OVIP_AXI_RESP_SLVERR) `uvm_error("RANGE", "a beat of the refused read is not SLVERR")

		// running past the end: 4 beats of 8 bytes from 0x7F0 reach 0x80F
		// (the range ends at 0x800, which is not a 4 KiB boundary)
		write_burst('h7F0, 3, wr);
		if(wr.resp != OVIP_AXI_RESP_SLVERR) `uvm_error("RANGE", $sformatf("write past the end answered %s, expected SLVERR", wr.resp.name()))
		if(mem.line_exists('h7F0)) `uvm_error("RANGE", "the write past the end touched the memory")

		// the report, once per refused request, when the knob is on
		slave_seq.report_out_of_range = 1;
		uvm_report_cb::add(null, catcher);
		write_burst('h3000, 0, wr);
		read_burst('h3000, 0, rd);
		uvm_report_cb::delete(null, catcher);
		if(catcher.caught != 2) `uvm_error("RANGE", $sformatf("expected 2 SLAVE_SEQ/OUT_OF_RANGE reports, got %0d", catcher.caught))
		if(wr.resp != OVIP_AXI_RESP_SLVERR || rd.resp != OVIP_AXI_RESP_SLVERR) `uvm_error("RANGE", "a reported request was not answered SLVERR")

		`uvm_info("RANGE", "slave out-of-range: inside OKAY with round trip, outside and past the end SLVERR with memory untouched, reports counted", UVM_LOW)
		phase.drop_objection(this);
	endtask : main_phase
endclass : ovip_axi_slave_out_of_range_test
