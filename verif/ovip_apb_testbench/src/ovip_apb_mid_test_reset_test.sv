`ifndef OVIP_APB_MID_TEST_RESET_TEST__SV
`define OVIP_APB_MID_TEST_RESET_TEST__SV

// A reset in the middle of a transfer, from a requester that drops PSEL with
// it, as an asynchronously reset one does (a NoC's NI). The completer holds
// PREADY low for 8 to 16 cycles, so the reset meets the transfer in ACCESS.
// Both monitors must take the reset as the end of the transfer, not as a
// protocol error, and the transfers after the release must run clean.
class ovip_apb_mid_test_reset_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_mid_test_reset_test)

	function new(string name = "ovip_apb_mid_test_reset_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function ovip_apb_base_slave_sequence create_slave_seq();
		ovip_apb_base_slave_sequence seq = super.create_slave_seq();
		seq.set_wait_states(8, 16);
		return seq;
	endfunction

	task main_phase(uvm_phase phase);
		virtual ovip_apb_agent_if vif = req_agent.mon.vif;
		ovip_apb_simple_rw_seq    pre = ovip_apb_simple_rw_seq::type_id::create("pre");
		ovip_apb_simple_rw_seq    post = ovip_apb_simple_rw_seq::type_id::create("post");
		super.main_phase(phase);
		phase.raise_objection(this);

		// a transfer waiting in ACCESS
		pre.num_transfers = 8;
		pre.data_width    = req_cfg.data_width;
		fork pre.start(req_agent.master_sqr); join_none
		@(posedge vif.pclk iff (vif.psel === 1'b1 && vif.penable === 1'b1 && vif.pready === 1'b0));
		#200ps;

		// the reset, and PSEL dropping with it
		`uvm_info("MID_RST_TEST", "=== mid-test reset asserted, PSEL dropped with it ===", UVM_LOW)
		disable fork;   // the sequence's cut transfer is not checked
		if(!uvm_hdl_force("tb.presetn", 1'b0) || !uvm_hdl_force("tb.apb_if.psel", 1'b0))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force failed -- adjust the HDL paths for your testbench")
		repeat(4) @(posedge vif.pclk);
		if(!uvm_hdl_release("tb.apb_if.psel"))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_release(tb.apb_if.psel) failed")
		repeat(4) @(posedge vif.pclk);
		req_agent.master_sqr.stop_sequences();
		if(!uvm_hdl_force("tb.presetn", 1'b1))
			`uvm_fatal("MID_RST_TEST", "uvm_hdl_force(tb.presetn) failed")
		repeat(4) @(posedge vif.pclk);
		`uvm_info("MID_RST_TEST", "=== mid-test reset deasserted ===", UVM_LOW)

		// transfers after the release, self-checked
		post.num_transfers = 16;
		post.data_width    = req_cfg.data_width;
		post.start(req_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
