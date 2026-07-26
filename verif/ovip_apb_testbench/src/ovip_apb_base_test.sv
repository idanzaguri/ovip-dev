`ifndef OVIP_APB_BASE_TEST__SV
`define OVIP_APB_BASE_TEST__SV

// Common base for every ovip_apb test:
//   - builds one requester agent (`req_agent`) and one completer agent
//     (`comp_agent`), both default ACTIVE, APB4 with PSTRB/PPROT/PSLVERR
//     enabled; subclasses tweak the cfg objects in build_phase (after
//     super.build_phase but before the end of the phase they can't -- so
//     overrides happen via the `configure_agents` hook below)
//   - creates a shared ovip_mem and starts the memory-backed base slave
//     sequence on the completer in run_phase (subclasses override
//     `create_slave_seq` to inject errors or directed wait states)
//   - installs ovip_apb_expected_errors_report_server so tests can register
//     expected errors via custom_report_server.expected_errors
//   - prints `SvtTestEpilog: Passed` / `Failed` at final_phase
class ovip_apb_base_test extends uvm_test;
	ovip_apb_expected_errors_report_server custom_report_server;

	ovip_apb_agent_config req_cfg;
	ovip_apb_agent_config comp_cfg;

	ovip_apb_agent req_agent;
	ovip_apb_agent comp_agent;

	ovip_mem mem;
	ovip_apb_base_slave_sequence slave_seq;

	uvm_active_passive_enum is_req_active;
	uvm_active_passive_enum is_comp_active;

	`uvm_component_utils(ovip_apb_base_test)

	function new(string name = "ovip_apb_base_test", uvm_component parent);
		super.new(name, parent);
		is_req_active  = UVM_ACTIVE;
		is_comp_active = UVM_ACTIVE;
	endfunction : new

	// Hook for subclasses to adjust the cfg objects after the base defaults
	// are applied and before the agents consume them.
	virtual function void configure_agents();
	endfunction : configure_agents

	// Hook for subclasses to supply a specialized completer sequence.
	virtual function ovip_apb_base_slave_sequence create_slave_seq();
		return ovip_apb_base_slave_sequence::type_id::create("slave_seq");
	endfunction : create_slave_seq

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		req_cfg  = ovip_apb_agent_config::type_id::create("req_cfg");
		comp_cfg = ovip_apb_agent_config::type_id::create("comp_cfg");

		req_cfg.agent_type = OVIP_APB_REQUESTER;
		req_cfg.is_active  = is_req_active;
		req_cfg.agent_tag  = "REQ";
		req_cfg.addr_width = 16;
		req_cfg.data_width = 4;
		req_cfg.pstrb_en   = 1;
		req_cfg.pprot_en   = 1;
		req_cfg.pslverr_en = 1;

		comp_cfg.agent_type = OVIP_APB_COMPLETER;
		comp_cfg.is_active  = is_comp_active;
		comp_cfg.agent_tag  = "COMP";
		comp_cfg.addr_width = 16;
		comp_cfg.data_width = 4;
		comp_cfg.pstrb_en   = 1;
		comp_cfg.pprot_en   = 1;
		comp_cfg.pslverr_en = 1;

		configure_agents();

		req_agent = ovip_apb_agent::type_id::create("req_agent", this);
		req_agent.cfg = req_cfg;
		comp_agent = ovip_apb_agent::type_id::create("comp_agent", this);
		comp_agent.cfg = comp_cfg;

		mem = ovip_mem::type_id::create("mem", this);

		custom_report_server = new;
		custom_report_server.in_order = 1;
		uvm_report_server::set_server(custom_report_server);
	endfunction : build_phase

	task reset_phase(uvm_phase phase);
		super.reset_phase(phase);
		phase.raise_objection(this);
		@(posedge req_agent.mon.vif.presetn);
		phase.drop_objection(this);
	endtask

	task run_phase(uvm_phase phase);
		super.run_phase(phase);
		if(comp_cfg.is_active == UVM_ACTIVE)
		begin
			slave_seq = create_slave_seq();
			slave_seq.mem = mem;
			fork slave_seq.start(comp_agent.slave_sqr); join_none
		end
	endtask : run_phase

	function void final_phase(uvm_phase phase);
		super.final_phase(phase);
		begin
			string expected_errors[$] = custom_report_server.expected_errors;
			custom_report_server.expected_errors.delete();
			foreach(expected_errors[ii])
				`uvm_error("APB_TEST/MISSING_EXP_ERROR", expected_errors[ii])
		end
		begin
			uvm_report_server svr = uvm_report_server::get_server();
			if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_WARNING) > 0)
				`uvm_info("final_phase", "\nSvtTestEpilog: Failed\n", UVM_LOW)
			else
				`uvm_info("final_phase", "\nSvtTestEpilog: Passed", UVM_LOW)
		end
	endfunction
endclass : ovip_apb_base_test

`endif
