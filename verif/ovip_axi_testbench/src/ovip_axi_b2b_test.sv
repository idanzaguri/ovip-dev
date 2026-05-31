// Verifies back-to-back behavior: zero-delay transactions, the address-then-
// data inter-channel timing under stress, and the ready-pattern handover
// between consecutive transactions. Drives writes and reads from multiple
// concurrent threads with different timing knobs so the driver/monitor can
// be exercised in close-spaced corner conditions.

class axi_b2b_seq extends uvm_sequence#(ovip_axi_trans);
	ovip_axi_base_slave_sequence slave_seq_h;
	int id;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	ovip_axi_slave_driver slave_driver;
	ovip_axi_master_driver master_driver;

	`uvm_object_utils(axi_b2b_seq)

	function new(string name = "axi_b2b_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_axi_trans tr = ovip_axi_trans::type_id::create("good_trans");
		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.size    = OVIP_AXI_SIZE_8B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		tr.id      = id+1;
		tr.len = 10;
		for(int ii=0; ii<=tr.len; ii++)
		begin
			tr.strb_beats.push_back('hff);
			tr.data_beats.push_back(ii);
		end

		slave_driver.put_wready_pattern('{0,1}); // always wready
		master_driver.put_bready_pattern('{0,1}); // always bready

		for(int ii=0; ii<10;ii++)
		begin
			`uvm_info("ZAG_DEBUG","ready start",UVM_LOW)
			slave_driver.put_awready_pattern('{5,1}); // awready low for 5 cycles and then stays high.
			start_item(tr);
			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			tr.data_delay[0] = ii;
			fork
				begin
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid);
					repeat(ii)
					begin
						if(p_sequencer.vif.monitor_cb.wvalid) `uvm_error("B2B/simple", "early wvalid")
						@(p_sequencer.vif.monitor_cb);
					end

					repeat(tr.len+1)
					begin
						if(p_sequencer.vif.monitor_cb.wvalid != 1) `uvm_error("B2B/simple", "missing wvalid")
						@(p_sequencer.vif.monitor_cb);
					end

					if(p_sequencer.vif.monitor_cb.bvalid != 1)
						`uvm_error("B2B/simple", "missing bvalid")
				end
				begin
					`uvm_info("ZAG_DEBUG","seq start",UVM_LOW)
					finish_item(tr);
				end
			join
			get_response(rsp);
			#100;
		end

		//
		// delay_until_next_addr & delay_until_next_data
		//
		begin
			ovip_axi_trans wr_tr[5];
			p_sequencer.set_arbitration(UVM_SEQ_ARB_STRICT_FIFO);

			foreach(wr_tr[jj])
			begin
				fork
					int ii = jj;
					begin
						wr_tr[ii] = ovip_axi_trans::type_id::create($sformatf("wr_tr[%0d]",ii));
						wr_tr[ii].tr_type = OVIP_AXI_WRITE_TRANS;
						wr_tr[ii].size    = OVIP_AXI_SIZE_8B;
						wr_tr[ii].burst   = OVIP_AXI_BURST_INCR;
						wr_tr[ii].id      = ii;
						wr_tr[ii].len = 2;

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
						repeat(30) @(p_sequencer.vif.monitor_cb);
						`uvm_fatal("btb","delay_until_next_*** timeout")
					end
					begin
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid  & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","1",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid  & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","2",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","3",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid  & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","4",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","5",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","6",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid  & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","7",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","8",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","9",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","10",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid  & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","11",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","12",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","13",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","14",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","15",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","16",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","17",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & ~p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","18",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","19",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","20",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.wvalid) `uvm_info("b2b","21",UVM_LOW)
					end
				join_any
				disable fork;
			end
			join

			repeat(5) get_response(rsp);
		end
		
		#20ns;

		//
		// bresp delay
		//
		slave_driver.put_awready_pattern('{$urandom_range(10,2),1});
		for(int ii=0; ii<6; ii++)
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("wr_trans");
			tr.tr_type = OVIP_AXI_WRITE_TRANS;
			tr.size    = OVIP_AXI_SIZE_8B;
			tr.burst   = OVIP_AXI_BURST_INCR;
			tr.id      = 7;
			tr.len     = 2;
			for(int xx=0; xx<=tr.len; xx++)
			begin
				tr.strb_beats.push_back('hff);
				tr.data_beats.push_back(xx);
			end

			slave_seq_h.min_bresp_delay = ii;
			slave_seq_h.max_bresp_delay = ii;

			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			fork
				begin
					start_item(tr);
					finish_item(tr);
					get_response(rsp);
				end
				begin
					fork
						// Address phase sampled
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.awvalid & p_sequencer.vif.monitor_cb.awready);
						// Last beat sampled
						@(p_sequencer.vif.monitor_cb iff
							p_sequencer.vif.monitor_cb.wvalid & p_sequencer.vif.monitor_cb.wlast & p_sequencer.vif.monitor_cb.wready);
					join
					repeat(ii)
					begin
						@(p_sequencer.vif.monitor_cb);
						if(p_sequencer.vif.monitor_cb.bvalid) `uvm_error("bresp_delay", "early bvalid")
					end
					@(p_sequencer.vif.monitor_cb);
					if(~p_sequencer.vif/*.monitor_cb*/.bvalid) `uvm_error("bresp_delay", $sformatf("missing bvalid %0x",p_sequencer.vif.monitor_cb.bvalid))
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
				tr.size    = OVIP_AXI_SIZE_8B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len = 3;
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
						rd_tr[ii].size    = OVIP_AXI_SIZE_8B;
						rd_tr[ii].burst   = OVIP_AXI_BURST_INCR;
						rd_tr[ii].id      = ii;
						rd_tr[ii].len = 2;
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
						`uvm_fatal("btb_rd","delay_until_next_addr timeout")
					end
					begin
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","1",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","2",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","3",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","4",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","5",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","6",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","7",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","8",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","9",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","10",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","11",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","12",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","13",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","14",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","15",UVM_LOW)
						@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.rvalid & p_sequencer.vif.monitor_cb.rlast) `uvm_info("b2b","16",UVM_LOW)
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
				tr.size    = OVIP_AXI_SIZE_8B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len = 1;
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
				repeat(tr.len+1)
				begin
					@(p_sequencer.vif.monitor_cb);
					if(!p_sequencer.vif.monitor_cb.rvalid) `uvm_error("btb_rd_simple", "missing rvalid!")
				end
				if(!p_sequencer.vif.monitor_cb.rlast) `uvm_error("btb_rd_simple", "missing rlast!")
			end
		join


		// no b2b response
		#50ns;
		for(int ii=0; ii<10; ii++)
		fork
			begin
				slave_seq_h.b2b_rd_resp_prob = 0;
				tr.tr_type = OVIP_AXI_READ_TRANS;
				tr.size    = OVIP_AXI_SIZE_8B;
				tr.burst   = OVIP_AXI_BURST_INCR;
				tr.id      = 0;
				tr.len     = 2;
				slave_seq_h.min_rdata_delay = ii*(tr.len+1);
				slave_seq_h.max_rdata_delay = ii*(tr.len+1);
				start_item(tr);
				finish_item(tr);
				get_response(rsp);
			end
			begin
				@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid & p_sequencer.vif.monitor_cb.arready);
				repeat(tr.len+1)
				begin
					repeat(ii)
					begin
						@(p_sequencer.vif.monitor_cb);
						if(p_sequencer.vif.monitor_cb.rvalid) `uvm_error("rd_dealy", "wrong rvalid!")
					end
					@(p_sequencer.vif.monitor_cb);
					if(!p_sequencer.vif.monitor_cb.rvalid) `uvm_error("rd_dealy", "missing rvalid!")
				end
				if(!p_sequencer.vif.monitor_cb.rlast) `uvm_error("rd_dealy", "missing rlast!")
			end
		join



		// no b2b response
		slave_driver.put_arready_pattern('{3,1},1);
		master_driver.put_rready_pattern('{3,1},1);
		#50ns;
		begin
			slave_seq_h.b2b_rd_resp_prob = 0;
			tr.addr    = 'h777;
			tr.tr_type = OVIP_AXI_READ_TRANS;
			tr.size    = OVIP_AXI_SIZE_8B;
			tr.burst   = OVIP_AXI_BURST_INCR;
			tr.id      = 0;
			tr.len     = 3;
			slave_seq_h.min_rdata_delay = 5*(tr.len+1);
			slave_seq_h.max_rdata_delay = 5*(tr.len+1);
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
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.arvalid  & p_sequencer.vif.monitor_cb.arready) `uvm_info("b2b","1",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","2",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","3",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","4",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","5",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","6",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","7",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","8",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","9",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","10",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","11",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","12",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","13",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","14",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","15",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","16",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","17",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","18",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","19",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","20",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","21",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","22",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","23",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff ~p_sequencer.vif.monitor_cb.rvalid) `uvm_info("b2b","24",UVM_LOW)
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.monitor_cb.rvalid & p_sequencer.vif.monitor_cb.rlast) `uvm_info("b2b","25",UVM_LOW)
				end
			join_any
			disable fork;
		end
		join
		get_response(rsp);


	endtask : body
endclass






class ovip_axi_b2b_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_b2b_test)

	function new(string name = "ovip_axi_b2b_test", uvm_component parent);
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
		super.main_phase(phase);
		phase.raise_objection(this);
		#10;
		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;
		slave_seq.min_rdata_delay = 0;
		slave_seq.max_rdata_delay = 0;

		begin
			axi_b2b_seq seq = axi_b2b_seq::type_id::create("seq");
			$cast(seq.slave_driver, slave_agent.drv);
			$cast(seq.master_driver, master_agent.drv);
			seq.slave_seq_h = slave_seq;
			seq.start(master_agent.sqr);
		end

		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass

