`ifndef OVIP_APB_SLAVE_OUT_OF_RANGE_TEST__SV
`define OVIP_APB_SLAVE_OUT_OF_RANGE_TEST__SV

// The completer answers PSLVERR outside its memory's valid ranges. The memory
// owns 4 KiB at 0; a write and a read inside are OKAY and the data round
// trips; a write and a read outside come back PSLVERR with the memory
// untouched and a read of 0. The report SLAVE_SEQ/OUT_OF_RANGE fires once per
// refused transfer when the knob is on.

class ovip_apb_out_of_range_catcher extends uvm_report_catcher;
	int caught;
	function new(string name = "ovip_apb_out_of_range_catcher");
		super.new(name);
	endfunction
	function action_e catch();
		if(get_id() == "SLAVE_SEQ/OUT_OF_RANGE") begin caught++; return CAUGHT; end
		return THROW;
	endfunction
endclass


class ovip_apb_out_of_range_seq extends ovip_apb_base_master_sequence;
	`uvm_object_utils(ovip_apb_out_of_range_seq)
	bit report_phase_only;     // 1: the two transfers the report is counted on

	function new(string name = "ovip_apb_out_of_range_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_apb_data_t rdata;
		bit slverr;
		if(report_phase_only)
		begin
			apb_write('h3000, 32'h1, , , slverr);
			if(!slverr) `uvm_error("RANGE", "a reported write was not answered PSLVERR")
			apb_read('h3000, rdata, slverr);
			if(!slverr) `uvm_error("RANGE", "a reported read was not answered PSLVERR")
			return;
		end
		apb_write('h10, 32'hCAFE_F00D, , , slverr);
		if(slverr) `uvm_error("RANGE", "write inside the range answered PSLVERR")
		apb_read('h10, rdata, slverr);
		if(slverr) `uvm_error("RANGE", "read inside the range answered PSLVERR")
		else if(rdata !== 32'hCAFE_F00D) `uvm_error("RANGE", $sformatf("read-back inside the range is 0x%0h", rdata))
		apb_write('h2000, 32'hBAD0_BAD0, , , slverr);
		if(!slverr) `uvm_error("RANGE", "write outside the range was not answered PSLVERR")
		apb_read('h2000, rdata, slverr);
		if(!slverr) `uvm_error("RANGE", "read outside the range was not answered PSLVERR")
		else if(rdata !== 0) `uvm_error("RANGE", $sformatf("the refused read returned 0x%0h", rdata))
	endtask
endclass


class ovip_apb_slave_out_of_range_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_slave_out_of_range_test)

	function new(string name = "ovip_apb_slave_out_of_range_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mem.add_valid_range('h0, 'h1000);          // the completer owns [0, 0x1000)
	endfunction

	task main_phase(uvm_phase phase);
		ovip_apb_out_of_range_seq seq = ovip_apb_out_of_range_seq::type_id::create("seq");
		ovip_apb_out_of_range_seq rep = ovip_apb_out_of_range_seq::type_id::create("rep");
		ovip_apb_out_of_range_catcher catcher = new();
		super.main_phase(phase);
		phase.raise_objection(this);
		slave_seq.report_out_of_range = 0;           // this test aims outside on purpose
		seq.start(req_agent.master_sqr);
		if(mem.line_exists('h2000)) `uvm_error("RANGE", "the refused write touched the memory")

		slave_seq.report_out_of_range = 1;
		rep.report_phase_only = 1;
		uvm_report_cb::add(null, catcher);
		rep.start(req_agent.master_sqr);
		uvm_report_cb::delete(null, catcher);
		if(catcher.caught != 2) `uvm_error("RANGE", $sformatf("expected 2 SLAVE_SEQ/OUT_OF_RANGE reports, got %0d", catcher.caught))
		`uvm_info("RANGE", "completer out-of-range: inside OKAY with round trip, outside PSLVERR with memory untouched, reports counted", UVM_LOW)
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
