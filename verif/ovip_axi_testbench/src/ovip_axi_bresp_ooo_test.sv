// Verifies write-response out-of-order behavior. The slave subclass returns
// BRESPs in deliberately mismatched order to the address-phase order; the
// monitor must accept the OoO completion when wr_resp_out_of_order_depth
// permits it, and flag it as AXI_MON/BRESP exceed when it doesn't.

class ovip_axi_bresp_ooo_slave_seq extends ovip_axi_base_slave_sequence;

	int tr_counter;
	int bresp_ooo_depth;
	int bresp_delay;
	`uvm_object_utils(ovip_axi_bresp_ooo_slave_seq)

	function new(string name = "ovip_axi_bresp_ooo_slave_seq");
		super.new(name);
		tr_counter = 0;
		bresp_ooo_depth = 10;
	endfunction

	virtual function int get_bresp_delay();
		if(tr_counter%(bresp_ooo_depth) == 0) bresp_delay = bresp_ooo_depth-1;
		else bresp_delay--;
		tr_counter++;
		return bresp_delay*2;
	endfunction : get_bresp_delay
endclass : ovip_axi_bresp_ooo_slave_seq



class ovip_axi_bresp_ooo_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_bresp_ooo_test)

	function new(string name = "ovip_axi_bresp_ooo_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(),ovip_axi_bresp_ooo_slave_seq::get_type());
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
		master_cfg.wr_resp_out_of_order_depth = 9;
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
		
		s_drv.put_awready_pattern('{0,1});
		s_drv.put_wready_pattern('{0,1});
		m_drv.put_bready_pattern('{0,1});

		// Verify AXI SLAVE WR resp out of order
		begin
			ovip_axi_simple_wr_bursts_seq seq = ovip_axi_simple_wr_bursts_seq::type_id::create("seq");
			seq.num_trans = 10;
			//repeat(seq.num_trans) seq.id.push_back(0);
			seq.min_burst_len = 0;
			seq.max_burst_len = 0;
			seq.min_delay_between_beats = 0;
			seq.max_delay_between_beats = 0;

			custom_report_server.expected_errors.push_back("AXI_MON.BRESP.*out of order depth \\(10\\) exceeded the allowed value \\(9\\)");
			seq.start(master_agent.sqr);
			#10ns;
		end
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi_bresp_ooo_test
