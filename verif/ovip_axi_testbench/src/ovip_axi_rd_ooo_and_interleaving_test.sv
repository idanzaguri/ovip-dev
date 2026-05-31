// Verifies the read-data out-of-order and interleaving paths. Two test classes
// share this file: ovip_axi_rd_ooo_test (multiple IDs, in-order beats per ID)
// and ovip_axi_rd_interleaving_test (multiple IDs, interleaved beats). Each
// drives the slave to return read data in patterns that violate the configured
// reorder/interleave depths so the monitor's AXI_MON/RDATA OoO and INTERLEAVING
// exceed checks fire.

class ovip_axi_read_ooo_slave_seq extends ovip_axi_base_slave_sequence;

	time target_time;
	time idle_time;
	time time_unit;
	`uvm_object_utils(ovip_axi_read_ooo_slave_seq)

	function new(string name = "ovip_axi_read_ooo_slave_seq");
		super.new(name);
		target_time = 0;
		idle_time = 20ns;
		time_unit = 1ns;
	endfunction

	virtual function void set_read_trans_delays(ovip_axi_trans tr);
		if($time > target_time)
			target_time += $time+idle_time;
		req.data_delay[0] = (target_time-$time)/time_unit;
	endfunction : set_read_trans_delays

endclass : ovip_axi_read_ooo_slave_seq




class ovip_axi_rd_ooo_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_rd_ooo_test)

	function new(string name = "ovip_axi_rd_ooo_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(),ovip_axi_read_ooo_slave_seq::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		master_cfg.num_outstanding_rd_transactions = 20;
		slave_cfg.num_outstanding_rd_transactions = 20;

		master_cfg.rd_out_of_order_depth = 1;
		master_cfg.rd_interleave_depth = 10;

		slave_cfg.rd_out_of_order_depth = 10;
		slave_cfg.rd_interleave_depth = 1;

		slave_cfg.drive_reset_values_when_idle = 0;
		slave_cfg.rd_scheduling_alg = OVIP_AXI_SCH_ALG_ALWAYS_LAST;
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			s_drv.put_arready_pattern('{0,1});
			m_drv.put_rready_pattern('{0,1});

			//
			// Out Of Order
			//
			seq.num_trans = 10;
			seq.min_burst_len = 0;
			seq.max_burst_len = 0;
			seq.min_delay_between_req = 0;
			seq.max_delay_between_req = 0;

			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(10\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(9\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(8\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(7\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(6\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(5\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(4\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(3\\) exceeded the allowed value \\(1\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*ut of order depth \\(2\\) exceeded the allowed value \\(1\\)");

			seq.start(master_agent.sqr);
			#10ns;
		end
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi_rd_ooo_test



class ovip_axi_rd_interleaving_test extends ovip_axi_rd_ooo_test;

	`uvm_component_utils(ovip_axi_rd_interleaving_test)

	function new(string name = "ovip_axi_rd_interleaving_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		slave_cfg.rd_out_of_order_depth = 10;
		slave_cfg.rd_interleave_depth = 10;

		master_cfg.rd_out_of_order_depth = 10;
		master_cfg.rd_interleave_depth = 2;

		slave_cfg.rd_scheduling_alg = OVIP_AXI_SCH_ALG_ROUND_ROBIN_REVERSED;
	endfunction : build_phase


	task main_phase(uvm_phase phase);
		//super.main_phase(phase);
		phase.raise_objection(this);

		begin
			ovip_axi_simple_rd_bursts_seq seq = ovip_axi_simple_rd_bursts_seq::type_id::create("seq");
			s_drv.put_arready_pattern('{0,1});
			m_drv.put_rready_pattern('{0,1});
			//
			// interleaving
			//
			seq.num_trans = 7;
			seq.addr = {0,0,0,0,0,0,0};
			seq.min_burst_len = seq.num_trans-1;
			seq.max_burst_len = seq.num_trans-1;
			seq.min_delay_between_req = 0;
			seq.max_delay_between_req = 0;

			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(3\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(4\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(5\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(6\\) exceeded the configured rd_interleave_depth \\(2\\)");
			repeat(37)
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(7\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(6\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(5\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(4\\) exceeded the configured rd_interleave_depth \\(2\\)");
			custom_report_server.expected_errors.push_back("AXI_MON.RDATA.*Read data interleaving \\(3\\) exceeded the configured rd_interleave_depth \\(2\\)");

			seq.start(master_agent.sqr);
		end
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi_rd_interleaving_test

