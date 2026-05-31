// Verifies the monitor's X/Z assertions (on by default; disable with
// `+define+OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS`). Forces X's
// onto various address/data/strobe signals while *valid is high and confirms
// the monitor fires AXI_MON/XZ_CHECK errors. Distinguishes the "X during a
// sampled cycle" case (real error) from the "X while *valid is low" case
// (legal, should NOT error).

class ovip_axi_xz_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_xz_test)

	function new(string name = "ovip_axi_xz_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;


		master_cfg.addr_width   = 20; slave_cfg.addr_width   = 20;
		master_cfg.wr_id_width  = 3;  slave_cfg.wr_id_width  = 3;
		master_cfg.rd_id_width  = 3;  slave_cfg.rd_id_width  = 3;
		master_cfg.len_width    = 7;  slave_cfg.len_width    = 7;
		master_cfg.size_width   = 2;  slave_cfg.size_width   = 2;
		master_cfg.awuser_width = 8;  slave_cfg.awuser_width = 8;
		master_cfg.wuser_width  = 8;  slave_cfg.wuser_width  = 8;
		master_cfg.buser_width  = 8;  slave_cfg.buser_width  = 8;
		master_cfg.aruser_width = 8;  slave_cfg.aruser_width = 8;
		master_cfg.ruser_width  = 8;  slave_cfg.ruser_width  = 8;
		master_cfg.awlock_en    = 1;  slave_cfg.awlock_en    = 1;
		master_cfg.awcache_en   = 1;  slave_cfg.awcache_en   = 1;
		master_cfg.awprot_en    = 1;  slave_cfg.awprot_en    = 1;
		master_cfg.awqos_en     = 1;  slave_cfg.awqos_en     = 1;
		master_cfg.awregion_en  = 1;  slave_cfg.awregion_en  = 1;
		master_cfg.arlock_en    = 1;  slave_cfg.arlock_en    = 1;
		master_cfg.arcache_en   = 1;  slave_cfg.arcache_en   = 1;
		master_cfg.arprot_en    = 1;  slave_cfg.arprot_en    = 1;
		master_cfg.arqos_en     = 1;  slave_cfg.arqos_en     = 1;
		master_cfg.arregion_en  = 1;  slave_cfg.arregion_en  = 1;

	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		// hand_shake_signals_xz_monitor
		begin
			// Small bias off the clock edge so the X-injection isn't sampled together with reset
			// deassertion on the same cycle (the monitor's reset-grace path would suppress it).
			#1ns;
			custom_report_server.in_order = 0;
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWVALID contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWREADY contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal WVALID contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal WREADY contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal BVALID contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal BREADY contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARVALID contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARREADY contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RVALID contains X's or Z's");
			custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RREADY contains X's or Z's");

			@(master_vif.monitor_cb);
			assert(uvm_hdl_force("tb.awvalid", 1'bx));
			assert(uvm_hdl_force("tb.awready", 1'bx));
			assert(uvm_hdl_force("tb.wvalid", 1'bx));
			assert(uvm_hdl_force("tb.wready", 1'bx));
			assert(uvm_hdl_force("tb.bvalid", 1'bx));
			assert(uvm_hdl_force("tb.bready", 1'bx));
			assert(uvm_hdl_force("tb.arvalid", 1'bx));
			assert(uvm_hdl_force("tb.arready", 1'bx));
			assert(uvm_hdl_force("tb.rvalid", 1'bx));
			assert(uvm_hdl_force("tb.rready", 1'bx));
			@(master_vif.monitor_cb);
			assert(uvm_hdl_release("tb.awvalid"));
			assert(uvm_hdl_release("tb.awready"));
			assert(uvm_hdl_release("tb.wvalid"));
			assert(uvm_hdl_release("tb.wready"));
			assert(uvm_hdl_release("tb.bvalid"));
			assert(uvm_hdl_release("tb.bready"));
			assert(uvm_hdl_release("tb.arvalid"));
			assert(uvm_hdl_release("tb.arready"));
			assert(uvm_hdl_release("tb.rvalid"));
			assert(uvm_hdl_release("tb.rready"));
			@(master_vif.monitor_cb);
			foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
			assert(custom_report_server.expected_errors.size() == 0);
		end

		#10ns;


		for(int ii=0; ii<2; ii++)
		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
			seq.num_trans = 1;
			seq.min_burst_len = 1;
			seq.max_burst_len = 1;
			`uvm_info("TEST/WRITE", $sformatf("------------ %0d ------------",ii+1),UVM_LOW)
			#10ns;
			// ii == 0: Good trans (XZ are not inside valid section)
			// ii == 1: Bad Trans
			assert(uvm_hdl_force($sformatf("tb.awaddr[%0d]",master_cfg.addr_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.awid[%0d]",master_cfg.wr_id_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.awlen[%0d]",master_cfg.len_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.awsize[%0d]",master_cfg.size_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.awuser[%0d]",master_cfg.awuser_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.wdata[%0d]",master_cfg.bus_width*8-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.wstrb[%0d]",master_cfg.bus_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.wuser[%0d]",master_cfg.wuser_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.buser[%0d]",master_cfg.buser_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.bid[%0d]",master_cfg.wr_id_width-ii), 1'bx));
			if(ii==1)
			begin
				assert(uvm_hdl_force("tb.awlock", 1'bx));
				assert(uvm_hdl_force("tb.awcache", 1'bx));
				assert(uvm_hdl_force("tb.awprot", 1'bx));
				assert(uvm_hdl_force("tb.awqos", 1'bx));
				assert(uvm_hdl_force("tb.awregion", 1'bx));
				assert(uvm_hdl_force("tb.bresp", 1'bx));
				custom_report_server.in_order = 0;
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWLOCK contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWCACHE contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWPROT contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWQOS contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWREGION contains X's or Z's");

				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWADDR contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWID contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWLEN contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWSIZE contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal AWUSER contains X's or Z's");
				repeat(2)
				begin
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal WDATA contains X's or Z's");
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal WSTRB contains X's or Z's");
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal WUSER contains X's or Z's");
				end
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal BUSER contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal BID contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal BRESP contains X's or Z's");

				custom_report_server.expected_errors.push_back("AXI_MON.INVALID_WSTRB");
				custom_report_server.expected_errors.push_back("AXI_MON.INVALID_WSTRB");
			end
			#10ns;
			seq.start(master_agent.sqr);
			assert(uvm_hdl_release("tb.awlock"));
			assert(uvm_hdl_release("tb.awcache"));
			assert(uvm_hdl_release("tb.awprot"));
			assert(uvm_hdl_release("tb.awqos"));
			assert(uvm_hdl_release("tb.awregion"));
			assert(uvm_hdl_release("tb.bresp"));
			assert(uvm_hdl_release($sformatf("tb.awaddr[%0d]",master_cfg.addr_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.awid[%0d]",master_cfg.wr_id_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.awlen[%0d]",master_cfg.len_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.awsize[%0d]",master_cfg.size_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.awuser[%0d]",master_cfg.awuser_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.wdata[%0d]",master_cfg.bus_width*8-ii)));
			assert(uvm_hdl_release($sformatf("tb.wstrb[%0d]",master_cfg.bus_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.wuser[%0d]",master_cfg.wuser_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.buser[%0d]",master_cfg.buser_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.bid[%0d]",master_cfg.wr_id_width-ii)));

			foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
			custom_report_server.expected_errors = custom_report_server.expected_errors.find(item) with (item != "AXI_MON.INVALID_WSTRB");
			assert(custom_report_server.expected_errors.size() == 0);
		end

		for(int ii=0; ii<2; ii++)
		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			seq.num_trans = 1;
			seq.min_burst_len = 1;
			seq.max_burst_len = 1;
			`uvm_info("TEST/READ", $sformatf("------------ %0d ------------",ii+1),UVM_LOW)
			#10ns;
			// ii == 0: Good trans (XZ are not inside valid section)
			// ii == 1: Bad Trans
			assert(uvm_hdl_force($sformatf("tb.araddr[%0d]",master_cfg.addr_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.arid[%0d]",master_cfg.rd_id_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.arlen[%0d]",master_cfg.len_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.arsize[%0d]",master_cfg.size_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.aruser[%0d]",master_cfg.aruser_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.rdata[%0d]",master_cfg.bus_width*8-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.ruser[%0d]",master_cfg.ruser_width-ii), 1'bx));
			assert(uvm_hdl_force($sformatf("tb.rid[%0d]",master_cfg.rd_id_width-ii), 1'bx));
			if(ii==1)
			begin
				assert(uvm_hdl_force("tb.arlock", 1'bx));
				assert(uvm_hdl_force("tb.arcache", 1'bx));
				assert(uvm_hdl_force("tb.arprot", 1'bx));
				assert(uvm_hdl_force("tb.arqos", 1'bx));
				assert(uvm_hdl_force("tb.arregion", 1'bx));
				assert(uvm_hdl_force("tb.rresp", 1'bx));
				custom_report_server.in_order = 0;
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARLOCK contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARCACHE contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARPROT contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARQOS contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARREGION contains X's or Z's");

				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARADDR contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARID contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARLEN contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARSIZE contains X's or Z's");
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal ARUSER contains X's or Z's");
				repeat(2)
				begin
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RID contains X's or Z's");
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RDATA contains X's or Z's");
					custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RUSER contains X's or Z's");
				end
				custom_report_server.expected_errors.push_back("AXI_MON.XZ_CHECK.*Signal RRESP contains X's or Z's");
			end
			#10ns;
			seq.start(master_agent.sqr);
			assert(uvm_hdl_release("tb.arlock"));
			assert(uvm_hdl_release("tb.arcache"));
			assert(uvm_hdl_release("tb.arprot"));
			assert(uvm_hdl_release("tb.arqos"));
			assert(uvm_hdl_release("tb.arregion"));
			assert(uvm_hdl_release("tb.rresp"));
			assert(uvm_hdl_release($sformatf("tb.araddr[%0d]",master_cfg.addr_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.arid[%0d]",master_cfg.rd_id_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.arlen[%0d]",master_cfg.len_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.arsize[%0d]",master_cfg.size_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.aruser[%0d]",master_cfg.aruser_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.rdata[%0d]",master_cfg.bus_width*8-ii)));
			assert(uvm_hdl_release($sformatf("tb.ruser[%0d]",master_cfg.ruser_width-ii)));
			assert(uvm_hdl_release($sformatf("tb.rid[%0d]",master_cfg.rd_id_width-ii)));

			foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
			assert(custom_report_server.expected_errors.size() == 0);

		end

		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass
