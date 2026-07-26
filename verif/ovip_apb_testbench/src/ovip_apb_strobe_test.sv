`ifndef OVIP_APB_STROBE_TEST__SV
`define OVIP_APB_STROBE_TEST__SV

// APB4 sparse-write coverage: writes a full word, then overwrites individual
// byte lanes with every strobe pattern, reading back after each step and
// checking against a locally-computed expected value. Proves the PSTRB path
// end to end (driver -> wire -> monitor -> slave sequence -> ovip_mem byte
// enables).
class ovip_apb_strobe_seq extends ovip_apb_base_master_sequence;
	`uvm_object_utils(ovip_apb_strobe_seq)

	ovip_apb_addr_t addr = 'h40;

	function new(string name = "ovip_apb_strobe_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_apb_data_t expected, rdata, pattern;
		bit slverr;

		// Full-word baseline.
		expected = 32'h0011_2233;
		apb_write(addr, expected, 4'hF, , slverr);
		if(slverr) `uvm_error("APB_STRB_TEST", "unexpected SLVERR on the baseline write")

		// Walk every strobe combination, merging locally to build `expected`.
		for(int unsigned strb = 0; strb < 16; strb++)
		begin
			pattern = {8'(strb*4+3), 8'(strb*4+2), 8'(strb*4+1), 8'(strb*4)} ^ 32'hA5A5_A5A5;
			apb_write(addr, pattern, ovip_apb_strb_t'(strb), , slverr);
			if(slverr) `uvm_error("APB_STRB_TEST", $sformatf("unexpected SLVERR on strobed write (strb=0x%0h)", strb))

			for(int b = 0; b < 4; b++)
				if(strb[b]) expected[b*8 +: 8] = pattern[b*8 +: 8];

			apb_read(addr, rdata, slverr);
			if(slverr)
				`uvm_error("APB_STRB_TEST", $sformatf("unexpected SLVERR on read-back (strb=0x%0h)", strb))
			else if(rdata !== expected)
				`uvm_error("APB_STRB_TEST", $sformatf("strobe merge mismatch after strb=0x%0h: expected 0x%0h, read 0x%0h",
					strb, expected, rdata))
		end
	endtask
endclass


class ovip_apb_strobe_test extends ovip_apb_base_test;
	`uvm_component_utils(ovip_apb_strobe_test)

	function new(string name = "ovip_apb_strobe_test", uvm_component parent);
		super.new(name, parent);
	endfunction

	task main_phase(uvm_phase phase);
		ovip_apb_strobe_seq seq = ovip_apb_strobe_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.start(req_agent.master_sqr);
		#200ns;
		phase.drop_objection(this);
	endtask
endclass

`endif
