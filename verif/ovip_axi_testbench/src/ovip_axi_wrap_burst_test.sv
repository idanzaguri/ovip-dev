// Verifies WRAP burst handling end-to-end.
//   Positive scenarios: WRAP writes followed by WRAP reads against ovip_mem
//     at several lengths {2,4,8,16}, sizes (narrow + full-width), and start
//     addresses (both wrap-aligned and wrap-spanning). Each beat round-trips
//     through memory and is compared against the value written.
//   Negative scenario: a WRAP transaction with a spec-illegal length (3 beats)
//     -- the monitor should flag it via AXI_MON/WR + AXI_MON/RD errors.


class ovip_axi_wrap_burst_test_seq extends ovip_axi_base_master_sequence;
	`uvm_object_utils(ovip_axi_wrap_burst_test_seq)
	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

	ovip_axi_addr_t start_addr;
	ovip_axi_size_t sz;
	int             len_val;

	function new(string name = "ovip_axi_wrap_burst_test_seq");
		super.new(name);
	endfunction

	virtual task body();
		int burst_size = 1 << sz;
		ovip_axi_data_t expected[$];

		// Write phase: deterministic data, full wstrb, capture for the read check.
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("wr");
			tr.tr_type = OVIP_AXI_WRITE_TRANS;
			tr.addr    = start_addr;
			tr.id      = 0;
			tr.len     = len_val;
			tr.size    = sz;
			tr.burst   = OVIP_AXI_BURST_WRAP;
			for(int bb = 0; bb <= len_val; bb++) begin
				ovip_axi_data_t v;
				v = (32'hC0DE_0000 | (int'(start_addr) << 4) | bb);
				v &= ((ovip_axi_data_t'(1) << (burst_size * 8)) - 1);
				tr.data_beats.push_back(v);
				tr.strb_beats.push_back((ovip_axi_strb_t'(1) << burst_size) - 1);
				expected.push_back(v);
			end
			send(tr);
			wait_for_responses();
		end

		// Read phase: same WRAP parameters; per-beat round-trip check.
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("rd");
			tr.tr_type = OVIP_AXI_READ_TRANS;
			tr.addr    = start_addr;
			tr.id      = 1;
			tr.len     = len_val;
			tr.size    = sz;
			tr.burst   = OVIP_AXI_BURST_WRAP;
			send(tr);
			wait_for_responses();
			foreach(tr.data_beats[bb]) begin
				if(tr.data_beats[bb] != expected[bb])
					`uvm_error("WRAP_DATA",
						$sformatf("addr=0x%0h len=%0d size=%s beat=%0d: read 0x%0h, wrote 0x%0h",
							start_addr, len_val, sz.name(), bb, tr.data_beats[bb], expected[bb]))
			end
		end
	endtask
endclass


class ovip_axi_wrap_burst_test extends ovip_axi_base_test;
	`uvm_component_utils(ovip_axi_wrap_burst_test)

	function new(string name = "ovip_axi_wrap_burst_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width     = OVIP_AXI_BUS_WIDTH_4B;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width      = OVIP_AXI_BUS_WIDTH_4B;

		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};
	endfunction

	task do_wrap_roundtrip(ovip_axi_addr_t addr_val, ovip_axi_size_t sz, int len_val);
		ovip_axi_wrap_burst_test_seq seq = ovip_axi_wrap_burst_test_seq::type_id::create("seq");
		seq.start_addr = addr_val;
		seq.sz         = sz;
		seq.len_val    = len_val;
		seq.start(master_agent.sqr);
	endtask

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		// Disable in_order so master and slave monitors firing in either order
		// can both match the same registered pattern.
		custom_report_server.in_order = 0;

		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;

		// Positive: 2-beat full-width, wrap-aligned start.
		do_wrap_roundtrip(.addr_val('h100), .sz(OVIP_AXI_SIZE_4B), .len_val(1));

		// Positive: 4-beat full-width, wrap-aligned.
		do_wrap_roundtrip(.addr_val('h200), .sz(OVIP_AXI_SIZE_4B), .len_val(3));

		// Positive: 4-beat full-width, wrap-spanning (start in middle of window).
		do_wrap_roundtrip(.addr_val('h308), .sz(OVIP_AXI_SIZE_4B), .len_val(3));

		// Positive: 8-beat narrow (size 2B on 4B bus), wrap-spanning.
		do_wrap_roundtrip(.addr_val('h402), .sz(OVIP_AXI_SIZE_2B), .len_val(7));

		// Positive: 16-beat full-width, wrap-aligned.
		do_wrap_roundtrip(.addr_val('h500), .sz(OVIP_AXI_SIZE_4B), .len_val(15));

		// Negative: spec-illegal WRAP length (3 beats == len 2). Master and
		// slave monitors both fire the AXI_MON/{WR,RD} error, so push the
		// pattern twice per direction.
		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("bad_wr");
			seq.num_trans = 1;
			seq.burst     = OVIP_AXI_BURST_WRAP;
			seq.size      = '{OVIP_AXI_SIZE_4B};
			seq.addr      = '{'h600};
			seq.len       = '{2};                       // 3 beats -- illegal
			seq.min_delay_between_beats = 0;
			seq.max_delay_between_beats = 0;
			custom_report_server.expected_errors.push_back("WRAP burst: length must be");
			custom_report_server.expected_errors.push_back("WRAP burst: length must be");
			seq.start(master_agent.sqr);
		end
		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("bad_rd");
			seq.burst = OVIP_AXI_BURST_WRAP;
			seq.size  = '{OVIP_AXI_SIZE_4B};
			seq.addr  = '{'h600};
			seq.len   = '{2};                           // 3 beats -- illegal
			custom_report_server.expected_errors.push_back("WRAP burst: length must be");
			custom_report_server.expected_errors.push_back("WRAP burst: length must be");
			seq.start(master_agent.sqr);
		end

		phase.drop_objection(this);
	endtask : main_phase

endclass
