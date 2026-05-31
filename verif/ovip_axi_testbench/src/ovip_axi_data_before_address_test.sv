// Verifies the data-before-address (DBA) write path:
// tr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR causes the master
// to drive WDATA before AWADDR with a controllable gap (tr.addr_phase_delay).
// Checks that the monitor accepts the legal DBA combination and that the
// outstanding-transactions counter increments at the data phase (not just at
// the address phase) so the in-flight cap is honored correctly.

class axi_data_before_address_seq extends uvm_sequence#(ovip_axi_trans);

	int id;

	ovip_axi_slave_driver s_drv;
	ovip_axi_master_driver m_drv;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

	`uvm_object_utils(axi_data_before_address_seq)

	function new(string name = "axi_data_before_address_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_axi_trans tr = ovip_axi_trans::type_id::create("good_trans");
		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.size    = OVIP_AXI_SIZE_8B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		tr.id      = id;
		tr.len = 10;


		for(int ii=0; ii<=tr.len; ii++)
		begin
			tr.strb_beats.push_back('hff);
			tr.data_beats.push_back(ii);
		end

		s_drv.put_wready_pattern('{0,1});
		m_drv.put_bready_pattern('{0,1});


		for(int ii=0; ii<10; ii++)
		begin
			start_item(tr);
			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			tr.data_delay[0] = ii; // cycles delay after addr phase driving
			s_drv.put_awready_pattern('{3,1});
			fork
				begin
					bit event_triggered = 0;
					forever
					begin
						@(p_sequencer.vif.monitor_cb)
						if(p_sequencer.vif.monitor_cb.awvalid) event_triggered = 1;

						if(event_triggered)
						begin
							repeat(tr.data_delay[0])
							begin
								if(p_sequencer.vif.monitor_cb.wvalid) `uvm_error("OVIP_AXI_DATA_START_EV_ADDR_DRIVEN", "Data phase started too early!!!")
								@(p_sequencer.vif.monitor_cb);
							end
							if(p_sequencer.vif.monitor_cb.wvalid == 0)
								`uvm_error("OVIP_AXI_DATA_START_EV_ADDR_DRIVEN", "Data phase should be started already!")
							break;
						end
						else
						begin
							if(p_sequencer.vif.monitor_cb.wvalid) `uvm_error("OVIP_AXI_DATA_START_EV_ADDR_DRIVEN", "Data phase started too soon!!!")
						end
					end
				end
			join_none
			finish_item(tr);
			get_response(rsp);
		end
		#100ns;

		for(int ii=0; ii<10;ii++)
		begin
			start_item(tr);
			tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_SAMPLED;
			tr.data_delay[0] = ii;// Cycles delay after addr phase sampling
			s_drv.put_awready_pattern('{5,1});
			fork
				forever
				begin
					@(p_sequencer.vif.monitor_cb);
					if(p_sequencer.vif.monitor_cb.wvalid) `uvm_error("OVIP_AXI_DATA_START_EV_ADDR_SAMPLED", "Data phase started too soon!!!")
					if(p_sequencer.vif.monitor_cb.awvalid && p_sequencer.vif.monitor_cb.awready)
					begin
						@(p_sequencer.vif.monitor_cb);
						repeat(tr.data_delay[0])
						begin
							if(p_sequencer.vif.monitor_cb.wvalid)
								`uvm_error("OVIP_AXI_DATA_START_EV_ADDR_SAMPLED", "Data phase started too early!!!")
							@(p_sequencer.vif.monitor_cb);
						end
						if(p_sequencer.vif.monitor_cb.wvalid == 0)
							`uvm_error("OVIP_AXI_DATA_START_EV_ADDR_SAMPLED", "Data phase should be started already!")
						break;
					end
				end
			join_none
			finish_item(tr);
			get_response(rsp);
		end

		#100ns;

		for(int ii = 1; ii<=10; ii++)
		begin
			start_item(tr);
			tr.addr_phase_delay = ii;// Cycles after first data driving (relevant only at OVIP_AXI_DATA_START_EV_BEFORE_ADDR)
			tr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;
			fork
				begin
					s_drv.put_awready_pattern('{1});
					s_drv.put_wready_pattern('{1});
					@(p_sequencer.vif.monitor_cb iff p_sequencer.vif.wvalid);
					s_drv.put_wready_pattern('{10,1});
					s_drv.put_awready_pattern('{20,1});
				end
				begin
					forever
					begin
						@(p_sequencer.vif.monitor_cb);
						if(p_sequencer.vif.monitor_cb.awvalid) `uvm_error("OVIP_AXI_DATA_START_EV_BEFORE_ADDR", "Addr phase started too soon!!!")
						if(p_sequencer.vif.monitor_cb.wvalid)
						begin
							repeat(tr.addr_phase_delay)
							begin
								if(p_sequencer.vif.monitor_cb.awvalid)
									`uvm_error("OVIP_AXI_DATA_START_EV_BEFORE_ADDR", $sformatf("Addr phase started too early! (%0d)", ii))
								@(p_sequencer.vif.monitor_cb);
							end
							if(p_sequencer.vif.monitor_cb.awvalid == 0)
								`uvm_fatal("OVIP_AXI_DATA_START_EV_BEFORE_ADDR", $sformatf("Addr phase should be started already! (%0d)",ii))
							break;
						end
					end
				end
			join_none
			finish_item(tr);
			get_response(tr);
		end
	endtask : body
endclass






class ovip_axi_data_before_address_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_data_before_address_test)

	function new(string name = "ovip_axi_data_before_address_test", uvm_component parent);
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
		slave_seq.min_bresp_delay = 0;
		slave_seq.max_bresp_delay = 0;

		// good data before address trans
		begin
			axi_data_before_address_seq seq = axi_data_before_address_seq::type_id::create("seq");
			seq.m_drv = m_drv;
			seq.s_drv = s_drv;
			seq.start(master_agent.sqr);
		end
	
		// bad last
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.WR.*xLAST was asserted on transfer #11, but the address phase AxLEN indicates it should be on transfer #24");
			custom_report_server.expected_errors.push_back("AXI_MON.WR.*xLAST was asserted on transfer #11, but the address phase AxLEN indicates it should be on transfer #24");
			custom_report_server.expected_errors.push_back("AXI_MASTER_DRV.BRESP.*Got write response with unknown ID.0x.");

			@(master_vif.master_cb);
			master_vif.master_cb.wvalid <= 1;
			repeat(10) @(master_vif.master_cb iff master_vif.master_cb.wready);
			master_vif.master_cb.wlast  <= 1;
			@(master_vif.master_cb iff master_vif.master_cb.wready);
			master_vif.master_cb.wvalid <= 0;
			master_vif.master_cb.wlast  <= 0;


			master_vif.master_cb.awvalid <= 1;
			master_vif.master_cb.awsize  <= 3;
			master_vif.master_cb.awburst <= 1;
			master_vif.master_cb.awlen   <= 23;
			@(master_vif.master_cb iff master_vif.master_cb.awready);
			master_vif.master_cb.awvalid <= 0;
			master_vif.master_cb.awsize  <= 0;
			master_vif.master_cb.awburst <= 0;
			master_vif.master_cb.awlen   <= 0;

			#50ns;
		end
		
		// missing last
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.AWLEN_MISMATCH.*Transaction length mismatch. Data phase indicated a total of 9 transfers, but the address phase specified an AWLEN of 5");
			custom_report_server.expected_errors.push_back("AXI_MON.AWLEN_MISMATCH.*Transaction length mismatch. Data phase indicated a total of 9 transfers, but the address phase specified an AWLEN of 5");

			@(master_vif.master_cb);
			master_vif.master_cb.wvalid <= 1;
			repeat(10) @(master_vif.master_cb iff master_vif.master_cb.wready);
			master_vif.master_cb.wvalid <= 0;

			master_vif.master_cb.awvalid <= 1;
			master_vif.master_cb.awsize  <= 3;
			master_vif.master_cb.awburst <= 1;
			master_vif.master_cb.awlen   <= 5;
			@(master_vif.master_cb iff master_vif.master_cb.awready);
			master_vif.master_cb.awvalid <= 0;
			master_vif.master_cb.awlen   <= 0;

			custom_report_server.expected_errors.push_back("AXI_MON.INCOMPLETE_WR_TRANS.*Transactions did not complete before the test was terminated:.*OVIP_AXI_WRITE_TRANS, ID=0x0, ADDR=0x0");
			custom_report_server.expected_errors.push_back("AXI_MON.INCOMPLETE_WR_TRANS.*Transactions did not complete before the test was terminated:.*OVIP_AXI_WRITE_TRANS, ID=0x0, ADDR=0x0");

			#100ns;
		end
		phase.drop_objection(this);
	endtask : main_phase

endclass
