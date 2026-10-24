`ifndef OVIP_APB_IDLE_PAYLOAD_TEST__SV
`define OVIP_APB_IDLE_PAYLOAD_TEST__SV

// The requester's randomize_idle_payload: random PADDR, PWRITE, PWDATA,
// PSTRB and PPROT while PSEL is LOW. Write / read-back traffic with random
// gaps, self-checked inside ovip_apb_simple_rw_seq, and the two monitors
// compared by the scoreboard, so an idle value never makes or changes a
// transfer. A watcher counts the idle cycles: PWRITE must be seen HIGH and
// PADDR and PWDATA non-zero while PSEL is LOW, and PENABLE must stay LOW.
class ovip_apb_idle_payload_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_idle_payload_test)

	ovip_apb_scoreboard sb;

	function new(string name = "ovip_apb_idle_payload_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void configure_agents();
		req_cfg.randomize_idle_payload = 1;
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		sb = ovip_apb_scoreboard::type_id::create("sb", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		req_agent.mon.analysis_port.connect(sb.exp_ap);
		comp_agent.mon.analysis_port.connect(sb.act_ap);
	endfunction

	task main_phase(uvm_phase phase);
		virtual ovip_apb_agent_if vif = req_agent.mon.vif;
		ovip_apb_simple_rw_seq    seq = ovip_apb_simple_rw_seq::type_id::create("seq");
		int  idle = 0, pwrite_hi = 0, paddr_nz = 0, pwdata_nz = 0, penable_hi = 0;
		bit  done = 0;
		super.main_phase(phase);
		phase.raise_objection(this);
		fork
			while (!done)
			begin
				@(vif.monitor_cb);
				if (vif.monitor_cb.presetn === 1'b1 && vif.monitor_cb.psel === 1'b0)
				begin
					idle++;
					if (vif.monitor_cb.pwrite === 1'b1) pwrite_hi++;
					if (vif.monitor_cb.paddr != '0) paddr_nz++;
					if (vif.monitor_cb.pwdata != '0) pwdata_nz++;
					if (vif.monitor_cb.penable !== 1'b0) penable_hi++;
				end
			end
		join_none
		seq.num_transfers = 32;
		seq.data_width    = req_cfg.data_width;
		seq.max_gap       = 6;
		seq.start(req_agent.master_sqr);
		#200ns;
		done = 1;
		if (pwrite_hi == 0 || paddr_nz == 0 || pwdata_nz == 0)
			`uvm_error("APB_IDLE_TEST", $sformatf("%0d idle cycles: PWRITE HIGH in %0d, PADDR non-zero in %0d, PWDATA non-zero in %0d; randomize_idle_payload must show all three",
				idle, pwrite_hi, paddr_nz, pwdata_nz))
		if (penable_hi != 0)
			`uvm_error("APB_IDLE_TEST", $sformatf("PENABLE was not LOW in %0d of %0d idle cycles", penable_hi, idle))
		`uvm_info("APB_IDLE_TEST", $sformatf("%0d idle cycles: PWRITE HIGH in %0d, PADDR non-zero in %0d, PWDATA non-zero in %0d", idle, pwrite_hi, paddr_nz, pwdata_nz), UVM_LOW)
		phase.drop_objection(this);
	endtask
endclass

`endif
