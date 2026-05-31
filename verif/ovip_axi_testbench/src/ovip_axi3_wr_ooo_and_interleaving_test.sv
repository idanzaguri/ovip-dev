// Verifies the AXI3-specific write paths -- out-of-order completion across IDs
// and W-channel data interleaving (an AXI3-only feature). Two test classes
// share one sequence: ovip_axi3_wr_ooo_test (multiple IDs, in-order data) and
// ovip_axi3_wr_interleaving_test (multiple IDs, interleaved data beats).

class ovip_axi3_ooo_wr_bursts_seq extends uvm_sequence#(ovip_axi_trans);

	bit interleaving_seq = 0;
	int num_trans = 10;

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_axi3_ooo_wr_bursts_seq)

	function new(string name = "ovip_axi3_ooo_wr_bursts_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_axi_trans tr_pool[] = new[num_trans];

		set_response_queue_depth(num_trans);

		foreach(tr_pool[idx])
		begin
			int ii = idx;
			begin
				ovip_axi_trans tr;
				tr_pool[ii] = ovip_axi_trans::type_id::create($sformatf("tr_pool[%0d]",ii));
				tr = tr_pool[ii];

				start_item(tr);
				tr.tr_type = OVIP_AXI_WRITE_TRANS;
				tr.addr  = 'h100*ii;
				tr.id    = ii;
				tr.len   = (interleaving_seq)? num_trans-1 : 1;
				tr.size  = ovip_axi_size_t'($clog2(p_sequencer.cfg.bus_width));
				tr.burst = OVIP_AXI_BURST_INCR;

				repeat(tr.len+1)
				begin
					tr.strb_beats.push_back($urandom & ((1<<p_sequencer.cfg.bus_width)-1));
					tr.data_beats.push_back($urandom & ((1<<(p_sequencer.cfg.bus_width*8))-1));

					if(tr.data_delay.size()==0)
						tr.data_delay.push_back(2+num_trans-ii);
					else
						tr.data_delay.push_back(0);
				end

				if(interleaving_seq)
				begin
					tr.data_delay = {};
					tr.data_delay[0] = 2*num_trans-ii;
				end

				finish_item(tr);
			end
		end

		foreach(tr_pool[ii])
		begin
			get_response(tr_pool[ii]);
		end

	endtask : body
endclass



class ovip_axi3_wr_ooo_slave_seq extends ovip_axi_base_slave_sequence;

	int tr_counter;
	int bresp_ooo_depth;
	int bresp_delay;
	`uvm_object_utils(ovip_axi3_wr_ooo_slave_seq)

	function new(string name = "ovip_axi3_wr_ooo_slave_seq");
		super.new(name);
		tr_counter = 0;
		bresp_ooo_depth = 10;
	endfunction

	virtual function int get_bresp_delay();
		if(tr_counter%(bresp_ooo_depth) == 0) bresp_delay = bresp_ooo_depth;
		else bresp_delay--;
		tr_counter++;
		return bresp_delay*2+20;
	endfunction : get_bresp_delay
endclass : ovip_axi3_wr_ooo_slave_seq



class ovip_axi3_wr_ooo_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi3_wr_ooo_test)

	function new(string name = "ovip_axi3_wr_ooo_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(),ovip_axi3_wr_ooo_slave_seq::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI3;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI3;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		slave_cfg.num_outstanding_transactions    = 20;
		slave_cfg.num_outstanding_wr_transactions = 20;

		master_cfg.wr_out_of_order_depth = 10; // <---- Only valid on AXI3
		master_cfg.wr_resp_out_of_order_depth = 10;
		master_cfg.wr_interleave_depth = 1;
		master_cfg.wr_scheduling_alg = OVIP_AXI_SCH_ALG_ALWAYS_LAST;

		slave_cfg.wr_out_of_order_depth = 1;
		slave_cfg.wr_resp_out_of_order_depth = 10;
		slave_cfg.wr_interleave_depth = 1;

	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		//
		// Verify AXI SLAVE WR resp out of order
		//
		s_drv.put_awready_pattern('{0,1});
		s_drv.put_wready_pattern('{0,1});
		m_drv.put_bready_pattern('{0,1});

		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(10\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(10\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(9\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(9\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(8\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(8\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(7\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(7\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(6\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(6\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(5\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(5\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(4\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(4\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(3\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(3\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(2\\) exceeded the allowed value \\(1\\)");
		custom_report_server.expected_errors.push_back("AXI_MON.*Out of order depth \\(2\\) exceeded the allowed value \\(1\\)");

		begin
			ovip_axi3_ooo_wr_bursts_seq seq = ovip_axi3_ooo_wr_bursts_seq::type_id::create("seq");
			seq.start(master_agent.sqr);
		end
		#10ns;
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi3_wr_ooo_test





class ovip_axi3_wr_interleaving_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi3_wr_interleaving_test)

	function new(string name = "ovip_axi3_wr_interleaving_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(),ovip_axi3_wr_ooo_slave_seq::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI3;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI3;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		slave_cfg.num_outstanding_transactions    = 20;
		slave_cfg.num_outstanding_wr_transactions = 20;

		master_cfg.wr_out_of_order_depth = 10; // <---- Only valid on AXI3
		master_cfg.wr_resp_out_of_order_depth = 10;
		master_cfg.wr_interleave_depth = 10;
		master_cfg.wr_scheduling_alg = OVIP_AXI_SCH_ALG_ROUND_ROBIN_REVERSED;

		slave_cfg.wr_out_of_order_depth = 10;
		slave_cfg.wr_resp_out_of_order_depth = 10;
		slave_cfg.wr_interleave_depth = 9;

	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		//
		// Verify AXI SLAVE WR resp out of order
		//
		begin
			ovip_axi3_ooo_wr_bursts_seq seq = ovip_axi3_ooo_wr_bursts_seq::type_id::create("seq");
			seq.num_trans = 10;
			seq.interleaving_seq = 1;
			s_drv.put_awready_pattern('{0,1});
			s_drv.put_wready_pattern('{0,1});
			m_drv.put_bready_pattern('{0,1});

			repeat(82)
			custom_report_server.expected_errors.push_back("AXI_MON.*Write data interleaving depth \\(10\\) exceeded configured limit \\(9\\)");

			seq.start(master_agent.sqr);
			#10ns;
		end
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi3_wr_interleaving_test
