`ifndef OVIP_AXI_STREAM_BASE_TEST__SV
`define OVIP_AXI_STREAM_BASE_TEST__SV

// Common base for every ovip_axi_stream test:
//   - builds one transmitter agent (`tx_agent`) and one receiver agent
//     (`rx_agent`), both default ACTIVE; subclasses override via
//     is_tx_active / is_rx_active in `new`
//   - installs ovip_axi_stream_expected_errors_report_server so tests can
//     register expected errors via custom_report_server.expected_errors
//   - prints `SvtTestEpilog: Passed` / `Failed` at final_phase
class ovip_axi_stream_base_test extends uvm_test;
	ovip_axi_stream_expected_errors_report_server custom_report_server;

	ovip_axi_stream_agent_config tx_cfg;
	ovip_axi_stream_agent_config rx_cfg;

	ovip_axi_stream_agent tx_agent;
	ovip_axi_stream_agent rx_agent;

	virtual ovip_axi_stream_agent_if tx_vif;
	virtual ovip_axi_stream_agent_if rx_vif;

	uvm_active_passive_enum is_tx_active;
	uvm_active_passive_enum is_rx_active;

	`uvm_component_utils(ovip_axi_stream_base_test)

	function new(string name = "ovip_axi_stream_base_test", uvm_component parent);
		super.new(name, parent);
		is_tx_active = UVM_ACTIVE;
		is_rx_active = UVM_ACTIVE;
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		tx_cfg = ovip_axi_stream_agent_config::type_id::create("tx_cfg");
		rx_cfg = ovip_axi_stream_agent_config::type_id::create("rx_cfg");

		tx_cfg.agent_type  = OVIP_AXI_STREAM_TRANSMITTER;
		tx_cfg.is_active   = is_tx_active;
		tx_cfg.tdata_width = 4;
		tx_cfg.tlast_en    = 1;
		tx_cfg.tkeep_en    = 1;
		tx_cfg.tstrb_en    = 1;
		tx_cfg.tid_en      = 1;  tx_cfg.tid_width   = 8;
		tx_cfg.tdest_en    = 1;  tx_cfg.tdest_width = 8;

		rx_cfg.agent_type  = OVIP_AXI_STREAM_RECEIVER;
		rx_cfg.is_active   = is_rx_active;
		rx_cfg.tdata_width = 4;
		rx_cfg.tlast_en    = 1;
		rx_cfg.tkeep_en    = 1;
		rx_cfg.tstrb_en    = 1;
		rx_cfg.tid_en      = 1;  rx_cfg.tid_width   = 8;
		rx_cfg.tdest_en    = 1;  rx_cfg.tdest_width = 8;

		tx_agent = ovip_axi_stream_agent::type_id::create("tx_agent", this);
		tx_agent.cfg = tx_cfg;
		rx_agent = ovip_axi_stream_agent::type_id::create("rx_agent", this);
		rx_agent.cfg = rx_cfg;

		custom_report_server = new;
		custom_report_server.in_order = 1;
		uvm_report_server::set_server(custom_report_server);
	endfunction : build_phase

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		tx_vif = tx_agent.mon.vif;
		rx_vif = rx_agent.mon.vif;
	endfunction : connect_phase

	task reset_phase(uvm_phase phase);
		super.reset_phase(phase);
		phase.raise_objection(this);
		@(posedge tx_agent.mon.vif.aresetn);
		phase.drop_objection(this);
	endtask

	function void final_phase(uvm_phase phase);
		super.final_phase(phase);
		begin
			string expected_errors[$] = custom_report_server.expected_errors;
			custom_report_server.expected_errors.delete();
			foreach(expected_errors[ii])
				`uvm_error("AXIS_TEST/MISSING_EXP_ERROR", expected_errors[ii])
		end
		begin
			uvm_report_server svr = uvm_report_server::get_server();
			if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_WARNING) > 0)
				`uvm_info("final_phase", "\nSvtTestEpilog: Failed\n", UVM_LOW)
			else
				`uvm_info("final_phase", "\nSvtTestEpilog: Passed", UVM_LOW)
		end
	endfunction
endclass : ovip_axi_stream_base_test

`endif
