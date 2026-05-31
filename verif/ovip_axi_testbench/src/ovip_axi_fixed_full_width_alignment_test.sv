// Verifies FIXED bursts with burst_size == bus_width (full-width) and
// auto_byte_lanes_alignment=1. The CHANGELOG/README originally flagged this
// combo as "not fully audited"; this test exercises it end-to-end.
//
// Configuration: bus_width = 4B (constrained by the slave sequence's
// `burst_size <= memory_word_size` rule, with the default WORD_SIZE = 4),
// SIZE_4B (== bus_width, so is_narrow_transfer == 0 on every beat), an
// aligned address, and a multi-beat FIXED burst. Same-address FIXED writes
// would collapse on a normal mem (only the last beat would be readable), so
// the mem is overridden to a small FIFO at the target address: each beat
// writes one entry, each read pops one entry, in order. The test compares
// the read beats against the written beats one-for-one.
//
// The code paths exercised:
//   - calculate_transfer_starting_byte_lane(): the non-narrow early-return.
//   - Master driver drive_w_channel: beat 0 takes the `burst_index == 0`
//     branch (shift by 0); beats 1..N take the raw-passthrough branch.
//   - Slave driver drive_rd_channel and monitor sample_*: symmetric.

`define FW_FIFO_ADDR 4

class ovip_mem_full_width_fifo extends ovip_mem;

	protected word_t fifo[$];

	`uvm_component_utils(ovip_mem_full_width_fifo)

	function new(string name = "ovip_mem_full_width_fifo", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	virtual function void write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);
		if(addr == `FW_FIFO_ADDR)
		begin
			word_t wdata = {WORD_SIZE{8'hAA}};
			byte_enable = -1; // full-width writes -- ignore byte strobes
			if (~|byte_enable) return;
			for (int i = 0; i < WORD_SIZE; i++)
				if (byte_enable[i])
					wdata[i*8 +: 8] = data[i*8 +: 8];
			fifo.push_back(wdata);
			return;
		end
		super.write(addr, data, byte_enable);
	endfunction : write

	function word_t read(addr_t addr);
		if(addr == `FW_FIFO_ADDR)
		begin
			if(fifo.size() == 0) `uvm_warning("OVIP_MEM/FIFO", "Reading from empty fifo!")
			return fifo.pop_front();
		end
		return super.read(addr);
	endfunction : read

endclass : ovip_mem_full_width_fifo


class ovip_axi_fixed_full_width_alignment_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_fixed_full_width_alignment_test)

	function new(string name = "ovip_axi_fixed_full_width_alignment_test", uvm_component parent);
		super.new(name, parent);
		set_inst_override_by_type("mem", ovip_mem::get_type(), ovip_mem_full_width_fifo::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width     = OVIP_AXI_BUS_WIDTH_4B;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width      = OVIP_AXI_BUS_WIDTH_4B;

		master_cfg.auto_byte_lanes_alignment = 1;
		slave_cfg.auto_byte_lanes_alignment  = 1;

		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		ovip_mem::word_t written_beats[$];
		super.main_phase(phase);
		phase.raise_objection(this);

		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;

		// FIXED write: every beat goes to the same address, FIFO stores them in order.
		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
			seq.num_trans = 1;
			seq.size      = '{OVIP_AXI_SIZE_4B}; // == bus_width (full-width)
			seq.addr      = '{`FW_FIFO_ADDR};
			seq.len       = '{4};                // 5 beats
			seq.burst     = OVIP_AXI_BURST_FIXED;
			seq.min_delay_between_beats = 0;
			seq.max_delay_between_beats = 0;
			seq.start(master_agent.sqr);
			foreach(seq.tr_pool[ii])
				foreach(seq.tr_pool[ii].data_beats[jj])
					written_beats.push_back(seq.tr_pool[ii].data_beats[jj]);
		end

		// FIXED read: same address, expect the FIFO contents in order.
		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			seq.burst = OVIP_AXI_BURST_FIXED;
			seq.size  = '{OVIP_AXI_SIZE_4B};
			seq.addr  = '{`FW_FIFO_ADDR};
			seq.len   = '{4};
			seq.start(master_agent.sqr);
			foreach(seq.tr_pool[ii])
				foreach(seq.tr_pool[ii].data_beats[jj])
					if(written_beats.pop_front() != seq.tr_pool[ii].data_beats[jj])
						`uvm_error("FIFO_POP_MISMATCH", $sformatf("beat[%0d] read=0x%0x", jj, seq.tr_pool[ii].data_beats[jj]))
		end

		phase.drop_objection(this);
	endtask : main_phase

endclass
