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
// It runs the pair twice: at an aligned address, then `FW_UNALIGNED_OFFSET
// bytes into the word. A FIXED burst repeats its address, so every beat of
// the unaligned pair uses only the byte lanes from that offset up (AXI
// A3.4.1). A VIP-to-VIP round trip cannot show a lane error, because both
// ends would make the same one, so the test also checks each beat's lanes
// on the bus.
//
// The code paths exercised:
//   - calculate_transfer_starting_byte_lane(): the FIXED branch, which comes
//     before the non-narrow early-return.
//   - Master driver drive_w_channel and sample_rd_response, slave driver
//     drive_rd_channel, monitor sample_*: every FIXED beat is shifted by the
//     first beat's lane (by 0 when aligned).

`define FW_FIFO_ADDR 4
`define FW_UNALIGNED_OFFSET 2

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
		ovip_axi_data_t  unaligned_beats[$];
		ovip_axi_data_t  bus_data[$];
		ovip_axi_strb_t  bus_strb[$];
		int nb = 4 - `FW_UNALIGNED_OFFSET;       // bytes each unaligned beat carries
		ovip_axi_data_t nb_mask = (ovip_axi_data_t'(1) << (nb * 8)) - 1;
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

		// Unaligned FIXED write: every beat carries its low `nb` bytes on
		// lanes FW_UNALIGNED_OFFSET..3, and strobes no lane below them.
		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
			seq.num_trans = 1;
			seq.size      = '{OVIP_AXI_SIZE_4B};
			seq.addr      = '{`FW_FIFO_ADDR + `FW_UNALIGNED_OFFSET};
			seq.len       = '{4};
			seq.burst     = OVIP_AXI_BURST_FIXED;
			seq.min_delay_between_beats = 0;
			seq.max_delay_between_beats = 0;
			fork : w_watch
				forever
				begin
					@(master_vif.monitor_cb iff master_vif.monitor_cb.wvalid && master_vif.monitor_cb.wready);
					bus_data.push_back(master_vif.monitor_cb.wdata);
					bus_strb.push_back(master_vif.monitor_cb.wstrb);
				end
			join_none
			seq.start(master_agent.sqr);
			disable w_watch;
			foreach(seq.tr_pool[0].data_beats[jj])
				unaligned_beats.push_back(seq.tr_pool[0].data_beats[jj] & nb_mask);
			foreach(bus_data[jj])
			begin
				if(bus_strb[jj] & ((1 << `FW_UNALIGNED_OFFSET) - 1))
					`uvm_error("FIXED_LANE", $sformatf("W beat[%0d] strobes a lane below the address: wstrb=%b", jj, bus_strb[jj]))
				if(((bus_data[jj] >> (`FW_UNALIGNED_OFFSET * 8)) & nb_mask) != unaligned_beats[jj])
					`uvm_error("FIXED_LANE", $sformatf("W beat[%0d] is not on the address's lanes: wdata=0x%0x, beat=0x%0x", jj, bus_data[jj], unaligned_beats[jj]))
			end
			if(bus_data.size() != unaligned_beats.size())
				`uvm_error("FIXED_LANE", $sformatf("saw %0d W beats on the bus, expected %0d", bus_data.size(), unaligned_beats.size()))
		end

		// Unaligned FIXED read: the same lanes on the bus, and the same bytes
		// back to the sequence, right-justified.
		bus_data.delete();
		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			seq.burst = OVIP_AXI_BURST_FIXED;
			seq.size  = '{OVIP_AXI_SIZE_4B};
			seq.addr  = '{`FW_FIFO_ADDR + `FW_UNALIGNED_OFFSET};
			seq.len   = '{4};
			fork : r_watch
				forever
				begin
					@(master_vif.monitor_cb iff master_vif.monitor_cb.rvalid && master_vif.monitor_cb.rready);
					bus_data.push_back(master_vif.monitor_cb.rdata);
				end
			join_none
			seq.start(master_agent.sqr);
			disable r_watch;
			foreach(bus_data[jj])
				if(jj < unaligned_beats.size()
				   && ((bus_data[jj] >> (`FW_UNALIGNED_OFFSET * 8)) & nb_mask) != unaligned_beats[jj])
					`uvm_error("FIXED_LANE", $sformatf("R beat[%0d] is not on the address's lanes: rdata=0x%0x, beat=0x%0x", jj, bus_data[jj], unaligned_beats[jj]))
			foreach(seq.tr_pool[0].data_beats[jj])
				if(jj < unaligned_beats.size() && seq.tr_pool[0].data_beats[jj] != unaligned_beats[jj])
					`uvm_error("FIFO_POP_MISMATCH", $sformatf("unaligned beat[%0d] read=0x%0x, written=0x%0x", jj, seq.tr_pool[0].data_beats[jj], unaligned_beats[jj]))
			if(bus_data.size() != unaligned_beats.size())
				`uvm_error("FIXED_LANE", $sformatf("saw %0d R beats on the bus, expected %0d", bus_data.size(), unaligned_beats.size()))
		end

		phase.drop_objection(this);
	endtask : main_phase

endclass
