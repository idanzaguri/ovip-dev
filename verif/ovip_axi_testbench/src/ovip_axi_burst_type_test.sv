// Verifies FIXED burst handling end-to-end. Two scenarios:
//   1. Negative: send a FIXED burst with len > 16 (spec-illegal) and check the
//      monitor's AXI_MON/WR + AXI_MON/RD "must not exceed 16" errors fire.
//   2. Positive: drive FIXED writes/reads against a FIFO-backed memory subclass
//      (every beat goes to the same address) and check the values round-trip
//      in order. Demonstrates that the slave-side reshape correctly preserves
//      same-address semantics across beats.

`define FIFO_ADDR 4

class ovip_mem_with_fifo extends ovip_mem;

	protected word_t fifo[$];

	`uvm_component_utils(ovip_mem_with_fifo)

	function new(string name = "ovip_mem_with_fifo", uvm_component parent);
		super.new(name, parent);
	endfunction : new


	virtual function void write(addr_t addr, word_t data, byte_enable_t byte_enable = -1);
		if(addr == `FIFO_ADDR)
		begin
			word_t wdata = {WORD_SIZE{8'hAA}};
			byte_enable = -1; // FIFO model intentionally ignores byte strobes -- it stores whole words
			if (~|byte_enable) return;
			
			for (int i = 0; i < WORD_SIZE; i++)
				if (byte_enable[i])
					wdata[i*8 +: 8] = data[i*8 +: 8];
			fifo.push_back(wdata);
			return;
		end
		super.write(addr,data,byte_enable);
	endfunction : write


	function word_t read(addr_t addr);
		if(addr == `FIFO_ADDR)
		begin
			if(fifo.size() == 0) `uvm_warning("OVIP_MEM/FIFO", "Reading from empty fifo!")
			return fifo.pop_front();
		end
		return super.read(addr);
	endfunction : read


endclass : ovip_mem_with_fifo


class ovip_axi_burst_type_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_burst_type_test)

	function new(string name = "ovip_axi_burst_type_test", uvm_component parent);
		super.new(name, parent);
		set_inst_override_by_type("mem", ovip_mem::get_type(), ovip_mem_with_fifo::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		master_cfg.num_outstanding_rd_transactions = 20;

		slave_cfg.num_outstanding_transactions    = 20;
		slave_cfg.num_outstanding_wr_transactions = 20;
		slave_cfg.num_outstanding_rd_transactions = 20;

		master_cfg.wr_out_of_order_depth = 1; // must be one for MASTER & AXI4
		master_cfg.wr_resp_out_of_order_depth = 10;
		master_cfg.wr_interleave_depth = 1;
		master_cfg.rd_out_of_order_depth = 10;
		master_cfg.rd_interleave_depth = 10;

		slave_cfg.wr_out_of_order_depth = 10;
		slave_cfg.wr_resp_out_of_order_depth = 10;
		slave_cfg.wr_interleave_depth = 10;
		slave_cfg.rd_out_of_order_depth = 10;
		slave_cfg.rd_interleave_depth = 10;

		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};

		slave_cfg.auto_byte_lanes_alignment = 1;
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);
		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;

		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
			seq.burst = OVIP_AXI_BURST_FIXED;
			seq.size = '{OVIP_AXI_SIZE_4B};
			seq.addr = '{0};   // pin to aligned addr -- the test is about the LEN>16 check, not WSTRB corners
			seq.max_burst_len = 16;
			seq.min_burst_len = seq.max_burst_len;
			seq.min_delay_between_beats = 0;
			seq.max_delay_between_beats = 0;
			custom_report_server.expected_errors.push_back("The length of a FIXED burst must not exceed 16 ");
			custom_report_server.expected_errors.push_back("The length of a FIXED burst must not exceed 16 ");
			seq.start(master_agent.sqr);
		end

		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			seq.burst = OVIP_AXI_BURST_FIXED;
			seq.size = '{OVIP_AXI_SIZE_4B};
			seq.addr = '{0};   // pin to aligned addr (see above)
			seq.max_burst_len = 16;
			seq.min_burst_len = seq.max_burst_len;
			custom_report_server.expected_errors.push_back("The length of a FIXED burst must not exceed 16 ");
			custom_report_server.expected_errors.push_back("The length of a FIXED burst must not exceed 16 ");
			seq.start(master_agent.sqr);
		end


		begin
			ovip_mem::word_t fifo[$];
			begin
				ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
				seq.num_trans = 1;
				seq.size = '{OVIP_AXI_SIZE_4B};
				seq.addr = '{`FIFO_ADDR};
				seq.len = '{10};
				seq.burst = OVIP_AXI_BURST_FIXED;
				seq.min_delay_between_beats = 0;
				seq.max_delay_between_beats = 0;
				seq.start(master_agent.sqr);
				foreach(seq.tr_pool[ii])
					foreach(seq.tr_pool[ii].data_beats[jj])
						fifo.push_back(seq.tr_pool[ii].data_beats[jj]);
				
			end
			begin
				ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
				seq.burst = OVIP_AXI_BURST_FIXED;
				seq.size = '{OVIP_AXI_SIZE_4B};
				seq.addr = '{`FIFO_ADDR};
				seq.len = '{10};
				seq.start(master_agent.sqr);
				foreach(seq.tr_pool[ii])
					foreach(seq.tr_pool[ii].data_beats[jj])
						if(fifo.pop_front() != seq.tr_pool[ii].data_beats[jj])
							`uvm_error("FIFO_POP_MISMATCH",$sformatf("0x%0x",seq.tr_pool[ii].data_beats[jj]))
			end
		end

		phase.drop_objection(this);
	endtask : main_phase

endclass
