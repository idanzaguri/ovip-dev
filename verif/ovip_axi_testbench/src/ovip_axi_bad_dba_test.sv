// Verifies the monitor's bad-data-before-address (DBA) error path: when the
// data phase starts before the address with a malformed combination (e.g.,
// AWLEN forced to a value that doesn't match the data-phase beat count), the
// monitor should fire AXI_MON/DBA / AXI_MON/AWLEN_MISMATCH. Uses uvm_hdl_force
// to inject the inconsistent AWLEN value.

class axi_bad_dba_seq extends uvm_sequence#(ovip_axi_trans);

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(axi_bad_dba_seq)

	function new(string name = "axi_bad_dba_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_axi_trans tr = ovip_axi_trans::type_id::create("good_trans");
		start_item(tr);

		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.size    = OVIP_AXI_SIZE_8B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		tr.id      = 1;
		tr.len = 10;

		for(int ii=0; ii<=tr.len; ii++)
		begin
			tr.strb_beats.push_back('hff);
			tr.data_beats.push_back(ii);
		end

		assert(uvm_hdl_force("tb.master_axi_if.awlen",11));

		tr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;
		tr.addr_phase_delay = 100;
		finish_item(tr);
		get_response(rsp);


		#100ns;
		start_item(tr);

		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.size    = OVIP_AXI_SIZE_8B;
		tr.burst   = OVIP_AXI_BURST_INCR;
		tr.id      = 2;
		tr.len = 10;

		for(int ii=0; ii<=tr.len; ii++)
		begin
			tr.strb_beats.push_back('hff);
			tr.data_beats.push_back(ii);
		end

		assert(uvm_hdl_force("tb.master_axi_if.awlen",9));

		tr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;
		tr.addr_phase_delay = 100;
		finish_item(tr);
		get_response(rsp);

	endtask : body
endclass






class ovip_axi_bad_dba_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_bad_dba_test)

	function new(string name = "ovip_axi_bad_dba_test", uvm_component parent);
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

		begin
			axi_bad_dba_seq seq = axi_bad_dba_seq::type_id::create("seq");
			custom_report_server.expected_errors.push_back("xLAST was asserted on transfer #11, but the address phase AxLEN indicates it should be on transfer #12.");
			custom_report_server.expected_errors.push_back("xLAST was asserted on transfer #11, but the address phase AxLEN indicates it should be on transfer #12.");
			custom_report_server.expected_errors.push_back("Transaction length mismatch. Data phase indicated a total of 10 transfers, but the address phase specified an AWLEN of 9!");
			custom_report_server.expected_errors.push_back("Transaction length mismatch. Data phase indicated a total of 10 transfers, but the address phase specified an AWLEN of 9!");

			seq.start(master_agent.sqr);
		end

		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass

