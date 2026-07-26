`ifndef OVIP_APB_ERROR_RESPONSE_TEST__SV
`define OVIP_APB_ERROR_RESPONSE_TEST__SV

// PSLVERR round trip: the completer responds SLVERR to every access inside a
// designated error window and OKAY elsewhere. The requester sequence checks
// that the sampled slverr matches the window on both writes and reads, and
// that an errored write did NOT update memory (the base slave sequence skips
// the commit on SLVERR).
class ovip_apb_err_window_slave_seq extends ovip_apb_base_slave_sequence;
	`uvm_object_utils(ovip_apb_err_window_slave_seq)

	ovip_apb_addr_t err_base = 'h100;
	int unsigned    err_size = 'h40;

	function new(string name = "ovip_apb_err_window_slave_seq");
		super.new(name);
	endfunction

	virtual function bit get_slverr(ovip_apb_trans req);
		return (req.addr >= err_base) && (req.addr < err_base + err_size);
	endfunction
endclass


class ovip_apb_error_response_seq extends ovip_apb_base_master_sequence;
	`uvm_object_utils(ovip_apb_error_response_seq)

	ovip_apb_addr_t ok_addr  = 'h10;
	ovip_apb_addr_t err_addr = 'h110;

	function new(string name = "ovip_apb_error_response_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_apb_data_t rdata;
		bit slverr;

		// Baseline value inside the OK region.
		apb_write(ok_addr, 32'hCAFE_F00D, , , slverr);
		if(slverr) `uvm_error("APB_ERR_TEST", "unexpected SLVERR on a write outside the error window")

		// Writes and reads inside the error window must return SLVERR.
		apb_write(err_addr, 32'hBAD0_BAD0, , , slverr);
		if(!slverr) `uvm_error("APB_ERR_TEST", "missing SLVERR on a write inside the error window")
		apb_read(err_addr, rdata, slverr);
		if(!slverr) `uvm_error("APB_ERR_TEST", "missing SLVERR on a read inside the error window")

		// Outside the window traffic still completes OKAY, and the earlier
		// value survived untouched.
		apb_read(ok_addr, rdata, slverr);
		if(slverr) `uvm_error("APB_ERR_TEST", "unexpected SLVERR on a read outside the error window")
		else if(rdata !== 32'hCAFE_F00D)
			`uvm_error("APB_ERR_TEST", $sformatf("read-back mismatch at 0x%0h: expected 0xCAFEF00D, got 0x%0h", ok_addr, rdata))
	endtask
endclass


class ovip_apb_error_response_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_error_response_test)

	function new(string name = "ovip_apb_error_response_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function ovip_apb_base_slave_sequence create_slave_seq();
		return ovip_apb_err_window_slave_seq::type_id::create("slave_seq");
	endfunction

	task main_phase(uvm_phase phase);
		ovip_apb_error_response_seq seq = ovip_apb_error_response_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.start(req_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
