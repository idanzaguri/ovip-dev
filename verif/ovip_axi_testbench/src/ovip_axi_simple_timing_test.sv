// Verifies the basic timing knobs on the trans:
//   - data_delay[] for per-beat read/write data spacing
//   - bresp_delay for write response gap
//   - delay_until_next_addr / delay_until_next_data between transactions
//   - data_start_event = ADDR_SAMPLED (and ADDR_DRIVEN as the default control)
// Drives loops over each delay knob in turn against a basic loopback so the
// monitor's timing assertions and the data integrity path can both observe
// the variations.

class ovip_axi_simple_timing_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_simple_timing_test)

	function new(string name = "ovip_axi_simple_timing_test", uvm_component parent);
		super.new(name, parent);
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

	endfunction : build_phase

	task main_phase(uvm_phase phase);
		ovip_axi_simple_wr_bursts_seq wr_seq = ovip_axi_simple_wr_bursts_seq::type_id::create("wr_seq");
		ovip_axi_simple_rd_bursts_seq rd_seq = ovip_axi_simple_rd_bursts_seq::type_id::create("rd_seq");
		wr_seq.num_trans = 1;
		rd_seq.num_trans = 1;
		slave_seq.b2b_rd_resp_prob = 0;

		super.main_phase(phase);
		phase.raise_objection(this);



		fork
			// READ channel
			begin
				for(int rdata_delay = 0; rdata_delay<5; rdata_delay++)
				begin
					rd_seq.min_burst_len = 4;
					rd_seq.max_burst_len = 4;
					slave_seq.rdelay_per_beat = 1;
					slave_seq.min_rdata_delay = rdata_delay;
					slave_seq.max_rdata_delay = rdata_delay;
					rd_seq.start(master_agent.sqr);
				end
			end

			// WRITE channel
			begin
				for(int bresp_delay = 0; bresp_delay<5; bresp_delay++)
				begin
					wr_seq.min_burst_len = 0;
					wr_seq.max_burst_len = 0;
					wr_seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_SAMPLED;
					slave_seq.min_bresp_delay = bresp_delay;
					slave_seq.max_bresp_delay = bresp_delay;
					wr_seq.start(master_agent.sqr);
				end

				for(int bresp_delay = 0; bresp_delay<5; bresp_delay++)
				begin
					wr_seq.min_burst_len = 3;
					wr_seq.max_burst_len = 3;
					wr_seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_SAMPLED;
					slave_seq.min_bresp_delay = bresp_delay;
					slave_seq.max_bresp_delay = bresp_delay;
					wr_seq.start(master_agent.sqr);
				end

				#50ns;

				for(int wr_delay = 0; wr_delay<5; wr_delay++)
				begin
					wr_seq.min_burst_len = 4;
					wr_seq.max_burst_len = 4;
					wr_seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_SAMPLED;
					wr_seq.min_delay_between_beats = wr_delay;
					wr_seq.max_delay_between_beats = wr_delay;
					slave_seq.min_bresp_delay = 0;
					slave_seq.max_bresp_delay = 0;
					wr_seq.start(master_agent.sqr);
				end
				#50ns;

				for(int wr_delay = 0; wr_delay<5; wr_delay++)
				begin
					wr_seq.min_burst_len = 4;
					wr_seq.max_burst_len = 4;
					wr_seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
					wr_seq.min_delay_between_beats = wr_delay;
					wr_seq.max_delay_between_beats = wr_delay;
					slave_seq.min_bresp_delay = 0;
					slave_seq.max_bresp_delay = 0;
					wr_seq.start(master_agent.sqr);
				end

			end
		join

		phase.drop_objection(this);
	endtask : main_phase

endclass

