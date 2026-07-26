`ifndef OVIP_APB_WAIT_STATES_TEST__SV
`define OVIP_APB_WAIT_STATES_TEST__SV

// Exercises PREADY stretching: back-to-back requester traffic (zero
// inter-transfer gap) against a completer that inserts 0..8 random wait
// states per transfer. The read-back self-check in ovip_apb_simple_rw_seq
// proves data integrity across wait states; the monitors verify the
// request-stability rules while PREADY is LOW; the scoreboard cross-checks
// the two monitors.
class ovip_apb_wait_states_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_wait_states_test)

	ovip_apb_scoreboard sb;

	function new(string name = "ovip_apb_wait_states_test", uvm_component parent);
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

	virtual function ovip_apb_base_slave_sequence create_slave_seq();
		ovip_apb_base_slave_sequence seq = super.create_slave_seq();
		seq.set_wait_states(0, 8);
		return seq;
	endfunction

	task main_phase(uvm_phase phase);
		ovip_apb_simple_rw_seq seq = ovip_apb_simple_rw_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.num_transfers = 32;
		seq.data_width    = req_cfg.data_width;
		seq.max_gap       = 0; // back-to-back: completion goes straight to the next SETUP
		seq.start(req_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
