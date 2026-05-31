// Verifies the monitor's signal-stability checks (on by default; disable with
// `+define+OVIP_AXI_DISABLE_XZ_AND_SIGNALS_STABILITY_CHECKS`). The test runs
// with both agents PASSIVE and uses uvm_hdl_force to inject glitches -- a
// *valid signal that de-asserts before the matching *ready samples it, an
// AxLEN that changes mid-handshake, etc. The monitor must fire
// AXI_MON/STABILITY_CHECK errors on each.

class ovip_axi_signal_stability_test extends ovip_axi_base_test;

	localparam STABILITY_TEST_ADDR = 1024; // arbitrary in-range address used by the stimulus

	`uvm_component_utils(ovip_axi_signal_stability_test)

	function new(string name = "ovip_axi_signal_stability_test", uvm_component parent);
		super.new(name, parent);
		is_master_active = UVM_PASSIVE;
		is_slave_active = UVM_PASSIVE;
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

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

	task reset_phase(uvm_phase phase);
		// NOTE: intentionally does NOT call super.reset_phase. The base reset_phase
		// blocks on @(posedge aresetn); this passive test must instead drive all
		// handshake signals to their idle (0) values immediately during reset so the
		// monitor does not observe spurious activity before main_phase drives them.
		phase.raise_objection(this);
		slave_vif.slave_cb.awready <= 0;
		slave_vif.slave_cb.wready <= 0;
		slave_vif.slave_cb.bvalid <= 0;
		master_vif.master_cb.awvalid <= 0;
		master_vif.master_cb.wvalid <= 0;
		master_vif.master_cb.bready <= 0;

		master_vif.master_cb.arvalid <= 0;
		master_vif.master_cb.rready <= 0;
		slave_vif.slave_cb.arready <= 0;
		slave_vif.slave_cb.rvalid <= 0;
		phase.drop_objection(this);
	endtask : reset_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		#10ns;

		`uvm_info("TEST", "------------ STABILITY WRITE 1 ------------",UVM_LOW)
		custom_report_server.in_order = 0;
		repeat(2)
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWID was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWADDR was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWSIZE was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWLEN was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWUSER was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWLOCK was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWPROT was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWCACHE was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWQOS was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWREGION was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal AWBURST was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*AWVALID was de-asserted before the transfer was sampled");
		end

		@(master_vif.master_cb);
		master_vif.master_cb.awvalid <= 1;
		master_vif.master_cb.awid    <= 1;
		master_vif.master_cb.awaddr  <= STABILITY_TEST_ADDR;
		master_vif.master_cb.awsize  <= 1;
		master_vif.master_cb.awlen   <= 1;
		master_vif.master_cb.awuser  <= 1;
		master_vif.master_cb.awlock  <= 1;
		master_vif.master_cb.awcache <= 1;
		master_vif.master_cb.awprot  <= 1;
		master_vif.master_cb.awqos   <= 1;
		master_vif.master_cb.awregion<= 1;
		master_vif.master_cb.awburst <= 1;
		@(master_vif.master_cb);
		master_vif.master_cb.awid    <= 0;
		master_vif.master_cb.awaddr  <= 0;
		master_vif.master_cb.awsize  <= 0;
		master_vif.master_cb.awlen   <= 0;
		master_vif.master_cb.awuser  <= 0;
		master_vif.master_cb.awlock  <= 0;
		master_vif.master_cb.awcache <= 0;
		master_vif.master_cb.awprot  <= 0;
		master_vif.master_cb.awqos   <= 0;
		master_vif.master_cb.awregion<= 0;
		master_vif.master_cb.awburst <= 0;
		@(master_vif.master_cb);
		master_vif.master_cb.awvalid <= 0;
		@(master_vif.master_cb);
		@(master_vif.master_cb);
		foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
		assert(custom_report_server.expected_errors.size() == 0);


		#10ns;
		`uvm_info("TEST", "------------ STABILITY WRITE 2 ------------",UVM_LOW)
		repeat(2)
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal WSTRB was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal WDATA was changed before being sampled");

			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal WUSER was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal WLAST was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*WVALID was de-asserted before the transfer was sampled");
		end

		@(master_vif.master_cb);
		master_vif.master_cb.wvalid <= 1;
		master_vif.master_cb.wid    <= 1;
		master_vif.master_cb.wuser  <= 1;
		master_vif.master_cb.wstrb  <= 1;
		master_vif.master_cb.wdata  <= 1;
		master_vif.master_cb.wlast  <= 1;
		@(master_vif.master_cb);
		master_vif.master_cb.wid    <= 0;
		master_vif.master_cb.wuser  <= 0;
		master_vif.master_cb.wstrb  <= 0;
		master_vif.master_cb.wdata  <= 0;
		master_vif.master_cb.wlast  <= 0;
		@(master_vif.master_cb);
		master_vif.master_cb.wvalid <= 0;
		@(master_vif.master_cb);

		foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
		assert(custom_report_server.expected_errors.size() == 0);

		#10ns;
		`uvm_info("TEST", "------------ STABILITY WRITE 3 ------------",UVM_LOW)
		custom_report_server.in_order = 0;
		repeat(2)
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal BID was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal BUSER was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal BRESP was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*BVALID was de-asserted before the transfer was sampled");
		end


		@(slave_vif.slave_cb);
		slave_vif.slave_cb.bid <= 1;
		slave_vif.slave_cb.buser <= 1;
		slave_vif.slave_cb.bresp <= 1;
		slave_vif.slave_cb.bvalid <= 1;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.bid <= 0;
		slave_vif.slave_cb.buser <= 0;
		slave_vif.slave_cb.bresp <= 0;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.bvalid <= 0;
		@(slave_vif.slave_cb);
		@(slave_vif.slave_cb);

		foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
		assert(custom_report_server.expected_errors.size() == 0);

		#10ns;

		`uvm_info("TEST", "------------ STABILITY READ 1 ------------",UVM_LOW)
		custom_report_server.in_order = 0;
		repeat(2)
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARID was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARADDR was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARSIZE was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARLEN was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARUSER was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARLOCK was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARPROT was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARCACHE was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARQOS was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARREGION was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal ARBURST was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*ARVALID was de-asserted before the transfer was sampled");
		end

		@(master_vif.master_cb);
		master_vif.master_cb.arvalid <= 1;
		master_vif.master_cb.arid    <= 1;
		master_vif.master_cb.araddr  <= STABILITY_TEST_ADDR;
		master_vif.master_cb.arsize  <= 1;
		master_vif.master_cb.arlen   <= 1;
		master_vif.master_cb.aruser  <= 1;
		master_vif.master_cb.arlock  <= 1;
		master_vif.master_cb.arcache <= 1;
		master_vif.master_cb.arprot  <= 1;
		master_vif.master_cb.arqos   <= 1;
		master_vif.master_cb.arregion<= 1;
		master_vif.master_cb.arburst <= 1;
		@(master_vif.master_cb);
		master_vif.master_cb.arid    <= 0;
		master_vif.master_cb.araddr  <= 0;
		master_vif.master_cb.arsize  <= 0;
		master_vif.master_cb.arlen   <= 0;
		master_vif.master_cb.aruser  <= 0;
		master_vif.master_cb.arlock  <= 0;
		master_vif.master_cb.arcache <= 0;
		master_vif.master_cb.arprot  <= 0;
		master_vif.master_cb.arqos   <= 0;
		master_vif.master_cb.arregion<= 0;
		master_vif.master_cb.arburst <= 0;
		@(master_vif.master_cb);
		master_vif.master_cb.arvalid <= 0;
		@(master_vif.master_cb);
		@(master_vif.master_cb);
		foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
		assert(custom_report_server.expected_errors.size() == 0);

		#10ns;
		`uvm_info("TEST", "------------ STABILITY READ 2 ------------",UVM_LOW)
		custom_report_server.in_order = 0;
		repeat(2)
		begin
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RID was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RUSER was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RRESP was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RRESP was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RDATA was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RLAST was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*Signal RLAST was changed before being sampled");
			custom_report_server.expected_errors.push_back("AXI_MON.STABILITY_CHECK.*RVALID was de-asserted before the transfer was sampled");
		end


		@(slave_vif.slave_cb);
		slave_vif.slave_cb.rid   <= 1;
		slave_vif.slave_cb.ruser  <= 1;
		slave_vif.slave_cb.rresp  <= 0;
		slave_vif.slave_cb.rlast  <= 0;
		slave_vif.slave_cb.rvalid <= 1;
		slave_vif.slave_cb.rdata <= 1;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.rid   <= 0;
		slave_vif.slave_cb.ruser  <= 0;
		slave_vif.slave_cb.rresp  <= 1;
		slave_vif.slave_cb.rlast  <= 1;
		slave_vif.slave_cb.rdata  <= 0;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.rresp  <= 0;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.rlast  <= 0;
		@(slave_vif.slave_cb);
		slave_vif.slave_cb.rvalid <= 0;
		@(slave_vif.slave_cb);
		@(slave_vif.slave_cb);

		foreach(custom_report_server.expected_errors[ii]) $display(custom_report_server.expected_errors[ii]);
		assert(custom_report_server.expected_errors.size() == 0);


		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

	task run_phase(uvm_phase phase);
		// disable slave seq
	endtask : run_phase

endclass

