// Common base for every ovip_axi test:
//   - builds master + slave agents (both default ACTIVE, override via
//     is_master_active / is_slave_active in subclass `new`)
//   - builds an ovip_mem instance and a default base slave sequence backed by it
//   - installs ovip_axi_expected_errors_report_server (see ovip_axi_expected_errors_report_server.sv) so tests can register
//     expected errors via custom_report_server.expected_errors
//   - prints the SvtTestEpilog: Passed/Failed line at final_phase
// Subclasses typically override build_phase (config tweaks) and main_phase
// (stimulus).

class ovip_axi_base_test extends uvm_test;
	ovip_axi_expected_errors_report_server custom_report_server;

	ovip_axi_agent_config master_cfg;
	ovip_axi_agent_config slave_cfg;

	ovip_axi_agent slave_agent;
	ovip_axi_agent master_agent;
	ovip_axi_master_driver m_drv;
	ovip_axi_slave_driver s_drv;

	ovip_mem mem;
	ovip_axi_base_slave_sequence slave_seq;

	virtual ovip_axi_agent_if master_vif;
	virtual ovip_axi_agent_if slave_vif;

	uvm_active_passive_enum is_master_active;
	uvm_active_passive_enum is_slave_active;

	`uvm_component_utils(ovip_axi_base_test)

	function new(string name = "ovip_axi_base_test", uvm_component parent);
		super.new(name, parent);
		is_master_active = UVM_ACTIVE;
		is_slave_active = UVM_ACTIVE;
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		mem = ovip_mem::type_id::create("mem", this);

		master_cfg = ovip_axi_agent_config::type_id::create("master_cfg");
		slave_cfg = ovip_axi_agent_config::type_id::create("slave_cfg");

		master_cfg.agent_type = OVIP_MASTER_AGENT;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		master_cfg.addr_width = 40;
		master_cfg.is_active = is_master_active;

		slave_cfg.agent_type = OVIP_SLAVE_AGENT;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.addr_width = 40;
		slave_cfg.is_active = is_slave_active;

		master_cfg.wr_id_width = 10;
		master_cfg.rd_id_width = 10;
		slave_cfg.wr_id_width = 10;
		slave_cfg.rd_id_width = 10;

		master_agent = ovip_axi_agent::type_id::create("master_agent",this);
		master_agent.cfg = master_cfg;

		slave_agent = ovip_axi_agent::type_id::create("slave_agent",this);
		slave_agent.cfg = slave_cfg;

		slave_seq = ovip_axi_base_slave_sequence::type_id::create("slave_seq");
		slave_seq.mem = mem;

		// Create and set the custom report server
		custom_report_server = new;
		custom_report_server.in_order = 1;
		uvm_report_server::set_server(custom_report_server);
	endfunction : build_phase

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		master_vif = master_agent.mon.vif;
		slave_vif = slave_agent.mon.vif;
		assert($cast(m_drv, master_agent.drv));
		assert($cast(s_drv, slave_agent.drv));
	endfunction : connect_phase

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		// The slave responder runs forever as a background process; it must not gate
		// the test, so no objection is raised here. End-of-test is controlled by the
		// per-test main_phase objections. The forked process lives for the run phase.
		fork
			slave_seq.start(slave_agent.sqr);
		join_none
	endtask : run_phase

	task reset_phase(uvm_phase phase);
		super.reset_phase(phase);
		phase.raise_objection(this);
		@(posedge master_agent.mon.vif.aresetn);
		phase.drop_objection(this);
	endtask

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction : report_phase

	function void final_phase(uvm_phase phase);
		super.final_phase(phase);
		begin
			string expected_errors[$] = custom_report_server.expected_errors;
			custom_report_server.expected_errors.delete();
			foreach(expected_errors[ii])
				`uvm_error("AXI_TEST/MISSING_EXP_ERROR", expected_errors[ii])
		end

		begin
			uvm_report_server svr;
			svr = uvm_report_server::get_server();
			if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_WARNING) > 0)
				`uvm_info("final_phase", "\nSvtTestEpilog: Failed\n", UVM_LOW)
			else
				`uvm_info("final_phase", "\nSvtTestEpilog: Passed", UVM_LOW)
		end
	endfunction


endclass : ovip_axi_base_test

