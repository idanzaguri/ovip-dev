`ifndef OVIP_APB_SMOKE_TEST__SV
`define OVIP_APB_SMOKE_TEST__SV

// Smallest end-to-end check: random write / read-back traffic from the
// requester against the memory-backed completer, self-checked inside
// ovip_apb_simple_rw_seq, plus a monitor-vs-monitor scoreboard: the
// requester-side monitor publishes "expected" transfers and the
// completer-side monitor "actual" ones. Pass = read-back data matches and
// both monitors agree on every transfer.
class ovip_apb_smoke_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_smoke_test)

	ovip_apb_scoreboard sb;

	function new(string name = "ovip_apb_smoke_test", uvm_component parent);
		super.new(name, parent);
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
		ovip_apb_simple_rw_seq seq = ovip_apb_simple_rw_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.num_transfers = 16;
		seq.data_width    = req_cfg.data_width;
		seq.start(req_agent.master_sqr);
		#200ns; // settle window so the last transfer's analysis writes land before final_phase
		phase.drop_objection(this);
	endtask
endclass

`endif
