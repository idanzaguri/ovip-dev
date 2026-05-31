// Verifies the AXI4-Lite protocol path: single-beat transactions only, fixed
// bus-aligned size, no AxLEN/AxBURST/AxLOCK/etc. Exercises lite-specific
// timing (BRESP after the last AWREADY+WREADY, arready-stalled awready),
// back-to-back transactions, randomized ready patterns, and id routing on
// the lite drivers/monitor.

class axi_lite_seq extends uvm_sequence#(ovip_axi_trans);
	ovip_axi_base_slave_sequence slave_seq_h;
	int id;
	ovip_axi_slave_driver slave_driver;
	ovip_axi_master_driver master_driver;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

	`uvm_object_utils(axi_lite_seq)

	function new(string name = "axi_lite_seq");
		super.new(name);
	endfunction

	virtual task body();

		ovip_axi_trans tr = ovip_axi_trans::type_id::create("good_trans");
		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.size    = OVIP_AXI_SIZE_4B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		tr.id      = id+1;
		tr.len = 0;

		tr.strb_beats[0] = 'hf;
		tr.data_beats[0] = $urandom;

		slave_driver.put_wready_pattern('{0,1}); // always wready
		master_driver.put_bready_pattern('{0,1}); // always bready
		
		slave_seq_h.min_bresp_delay = 0;
		slave_seq_h.max_bresp_delay = 0;

		for(int ii=0; ii<10;ii++)
		begin
			slave_driver.put_awready_pattern('{5,1}); // awready low for 5 cycles and then stays high.
			start_item(tr);
			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			tr.data_delay[0] = ii;
			fork
				begin
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid);
					repeat(ii)
					begin
						if(p_sequencer.vif.monitor_cb.wvalid) `uvm_error("lite/simple", "early wvalid")
						@(p_sequencer.vif.monitor_cb);
					end
					if(p_sequencer.vif.monitor_cb.wvalid != 1) `uvm_error("lite/simple", "missing wvalid")
				end
	
				begin
					fork
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.awready);
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
					join
					@(p_sequencer.vif.monitor_cb);
					if(p_sequencer.vif.monitor_cb.bvalid != 1)
						`uvm_error("lite/simple", "missing bvalid")
				end

				begin
					finish_item(tr);
				end
			join
			get_response(rsp);
		end
		
		//
		// delay_until_next_addr & delay_until_next_data
		//
		begin
			ovip_axi_trans wr_tr[4];
			p_sequencer.set_arbitration(UVM_SEQ_ARB_STRICT_FIFO);

			foreach(wr_tr[jj])
			begin
				fork
					int ii = jj;
					begin
						wr_tr[ii] = ovip_axi_trans::type_id::create($sformatf("wr_tr[%0d]",ii));
						wr_tr[ii].tr_type = OVIP_AXI_WRITE_TRANS;
						wr_tr[ii].size    = OVIP_AXI_SIZE_4B;
						wr_tr[ii].burst   = OVIP_AXI_BURST_INCR;
						wr_tr[ii].id      = ii;
						wr_tr[ii].len = 0;

						for(int xx=0; xx<=wr_tr[ii].len; xx++)
						begin
							wr_tr[ii].strb_beats.push_back('hff);
							wr_tr[ii].data_beats.push_back(xx);
							wr_tr[ii].data_delay[xx] = 0;
						end
						wr_tr[ii].data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
						wr_tr[ii].delay_until_next_addr = ii;
						wr_tr[ii].delay_until_next_data = ii;

						start_item(wr_tr[ii], 5-ii);
						finish_item(wr_tr[ii]);
					end
				join_none
			end

			fork
			begin
				fork
					begin
						repeat(1000) @(p_sequencer.vif.monitor_cb);
						`uvm_fatal("btb","delay_until_next_*** timeout")
					end
					begin
						fork
							begin
								repeat(1) @(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
								`uvm_info("b2b","11",UVM_LOW)
								@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.bvalid);
								`uvm_info("b2b","11",UVM_LOW)
							end
							begin
								repeat(2) @(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
								`uvm_info("b2b","22",UVM_LOW)
								@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.bvalid);
								`uvm_info("b2b","22",UVM_LOW)
							end
							begin
								repeat(3) @(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
								`uvm_info("b2b","33",UVM_LOW)
								@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.bvalid);
								`uvm_info("b2b","33",UVM_LOW)
							end
							begin
								repeat(4) @(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
								`uvm_info("b2b","44",UVM_LOW)
								@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.bvalid);
								`uvm_info("b2b","44",UVM_LOW)
							end
						join
					end
				join_any
				disable fork;
			end
			join

			foreach(wr_tr[jj]) get_response(rsp);
		end

		//
		// bresp delay
		//
		#20ns;
		for(int ii=0; ii<1; ii++)
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("wr_trans");
			tr.tr_type = OVIP_AXI_WRITE_TRANS;
			tr.size    = OVIP_AXI_SIZE_4B;
			tr.burst   = OVIP_AXI_BURST_INCR;
			tr.id      = 7;
			tr.len     = 0;
			
			tr.strb_beats[0] = 'hff;
			tr.data_beats[0] = $urandom;

			slave_seq_h.min_bresp_delay = ii;
			slave_seq_h.max_bresp_delay = ii;

			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			fork
				begin
					fork
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.awready);
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wready);
					join
					repeat(ii)
					begin
						@(p_sequencer.vif.monitor_cb);
						if(p_sequencer.vif.monitor_cb.bvalid) `uvm_error("bresp_delay", "early bvalid")
					end
					@(p_sequencer.vif.monitor_cb);
					if(~p_sequencer.vif./*monitor_cb.*/bvalid) `uvm_error("bresp_delay", "missing bvalid")
				end
				begin
					start_item(tr);
					finish_item(tr);
					get_response(rsp);
				end
			join
		end
		
		//
		// READ
		//
		#20ns;
		slave_driver.put_arready_pattern('{0,1}); // always arready
		master_driver.put_rready_pattern('{0,1}); // always rready

		fork
			begin
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len = 0;
				start_item(tr);
				finish_item(tr);
				get_response(rsp);
			end
			begin
				@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid);
				repeat(tr.len+1)
				begin
					@(p_sequencer.vif.monitor_cb);
					if(!p_sequencer.vif.monitor_cb.rvalid) `uvm_error("btb_rd_simple", "missing rvalid!")
				end
				if(!p_sequencer.vif.monitor_cb.rlast) `uvm_error("btb_rd_simple", "missing rlast!")
			end
		join

		#10ns;
		// delay_until_next_addr & delay_until_next_data
		begin
			ovip_axi_trans rd_tr[5];
			p_sequencer.set_arbitration(UVM_SEQ_ARB_STRICT_FIFO);

			foreach(rd_tr[jj])
			begin
				fork
					int ii = jj;
					begin
						rd_tr[ii] = ovip_axi_trans::type_id::create($sformatf("rd_tr[%0d]",ii));
						rd_tr[ii].tr_type = OVIP_AXI_READ_TRANS;
						rd_tr[ii].size    = OVIP_AXI_SIZE_4B;
						rd_tr[ii].burst   = OVIP_AXI_BURST_INCR;
						rd_tr[ii].id      = ii;
						rd_tr[ii].len     = 0;
						rd_tr[ii].delay_until_next_addr = ii;

						start_item(rd_tr[ii], 5-ii);
						finish_item(rd_tr[ii]);
					end
				join_none
			end

			fork
			begin
				fork
					begin
						repeat(20) @(p_sequencer.vif.monitor_cb);
						`uvm_fatal("axi_lite","delay_until_next_addr timeout")
					end
					begin
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid);
						for(int ii=0; ii<4;ii++)
						begin
							repeat(ii) @(p_sequencer.vif.monitor_cb);
							@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid);
						end
					end
				join_any
				disable fork;
			end
			join

			repeat(5) get_response(rsp);
		end
		
		// b2b response
		#20ns;
		for(int ii=0; ii<10; ii++)
		fork
			begin
				slave_seq_h.b2b_rd_resp_prob = 100;
				slave_seq_h.min_rdata_delay = ii;
				slave_seq_h.max_rdata_delay = ii;
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len = 0;
				start_item(tr);
				finish_item(tr);
				get_response(rsp);
			end
			begin
				@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.arready);
				repeat(ii)
				begin
					@(p_sequencer.vif.monitor_cb);
					if(p_sequencer.vif.monitor_cb.rvalid) `uvm_error("btb_rd_simple", "early rvalid!")
				end
				begin
					@(p_sequencer.vif.monitor_cb);
					if(!p_sequencer.vif.monitor_cb.rvalid) `uvm_error("btb_rd_simple", "missing rvalid!")
				end
			end
		join

		clear_response_queue();
		// no b2b response
		#50ns;
		for(int ii=0; ii<10; ii++)
		fork
			begin
				slave_seq_h.b2b_rd_resp_prob = 0;
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.size    = OVIP_AXI_SIZE_4B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len     = 0;
				slave_seq_h.min_rdata_delay = ii;
				slave_seq_h.max_rdata_delay = ii;
				start_item(tr);
				finish_item(tr);
				get_response(rsp);
			end
			begin
				@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.arready);
				repeat(ii) @(p_sequencer.vif.monitor_cb) if(p_sequencer.vif.monitor_cb.rvalid) `uvm_error("rd_dealy", "wrong rvalid!")
				@(p_sequencer.vif.monitor_cb);
				if(!p_sequencer.vif.monitor_cb.rvalid) `uvm_error("rd_dealy", "missing rvalid!")
			end
		join


		// no b2b response
		for(int qq=0; qq<2; qq++) begin
			ovip_axi_ready_pattern_t ready_pattern;
			repeat($urandom_range(5,4)) ready_pattern.cycles.push_back($urandom_range(3,1));
			ready_pattern.loop = 1;
			if(qq == 0) slave_driver.arready_pattern_mb.put(ready_pattern);
			else master_driver.rready_pattern_mb.put(ready_pattern);
		end

		#50ns;
		begin
			slave_seq_h.b2b_rd_resp_prob = 0;
			slave_seq_h.min_rdata_delay = 5;
			slave_seq_h.max_rdata_delay = 5;
			
			tr.addr    = 'h777;
			tr.tr_type = OVIP_AXI_READ_TRANS;
			start_item(tr);
			finish_item(tr);
		end


		fork
		begin
			fork
				begin
					repeat(30) @(p_sequencer.vif.monitor_cb);
					`uvm_fatal("btb","rd_delay*** timeout")
				end
				begin
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.arready);
					`uvm_info("lite","ADDR PHASE Sampled! waiting 5 seq for rvalid",UVM_LOW)
					for(int mm=0; mm<slave_seq_h.min_rdata_delay; mm++) begin
						@(p_sequencer.vif.monitor_cb);
						if(p_sequencer.vif.monitor_cb.rvalid) `uvm_error("axi_lite",$sformatf("wrong rvalid %0d",mm))
					end
					@(p_sequencer.vif.monitor_cb) if(~p_sequencer.vif/*.monitor_cb*/.rvalid) `uvm_error("axi_lite","missing rvalid")
				end
			join_any
			disable fork;
		end
		join
		get_response(rsp);


	endtask : body
endclass






class ovip_axi_4lite_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_4lite_test)

	function new(string name = "ovip_axi_4lite_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4_LITE;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_4B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4_LITE;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_4B;

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		master_cfg.num_outstanding_rd_transactions = 20;

		slave_cfg.num_outstanding_transactions    = 20;
		slave_cfg.num_outstanding_wr_transactions = 20;
		slave_cfg.num_outstanding_rd_transactions = 20;

		master_cfg.wr_out_of_order_depth = 1; // must be one for MASTER & AXI4
		master_cfg.wr_resp_out_of_order_depth = 1;
		master_cfg.wr_interleave_depth = 1;
		master_cfg.rd_out_of_order_depth = 1;
		master_cfg.rd_interleave_depth = 1;

		slave_cfg.wr_out_of_order_depth = 1;
		slave_cfg.wr_resp_out_of_order_depth = 1;
		slave_cfg.wr_interleave_depth = 1;
		slave_cfg.rd_out_of_order_depth = 1;
		slave_cfg.rd_interleave_depth = 1;

	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);
		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;
		slave_seq.min_rdata_delay = 0;
		slave_seq.max_rdata_delay = 0;

		begin
			axi_lite_seq seq = axi_lite_seq::type_id::create("seq");
			$cast(seq.slave_driver, slave_agent.drv);
			$cast(seq.master_driver, master_agent.drv);
			seq.slave_seq_h = slave_seq;
			seq.start(master_agent.sqr);
		end

		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass

