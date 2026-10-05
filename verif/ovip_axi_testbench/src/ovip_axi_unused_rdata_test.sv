// Verifies cfg.randomize_unused_rdata. With it set, the slave puts a random
// value on every RDATA byte lane that a narrow or unaligned beat does not
// use. For every burst size it reads a random bytestream back from an
// unaligned address and checks two things: the master got exactly the bytes
// the memory holds, and the bus carried non-zero bytes on lanes outside each
// beat's bytes, which it never does with the switch off.

class ovip_axi_unused_rdata_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_unused_rdata_test)

	typedef struct {
		ovip_axi_addr_t addr;
		int             size;   // bytes per beat
		int             beat;   // the next beat to arrive
	} ar_t;

	ar_t ar_q[$];             // the reads in flight, in AR order (one ID, so R comes back in that order)
	int  n_unused;            // RDATA bytes seen outside their beat's bytes
	int  n_unused_nonzero;    // of them, the ones that were not zero

	function new(string name = "ovip_axi_unused_rdata_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		slave_cfg.randomize_unused_rdata = 1;
		master_cfg.num_outstanding_rd_transactions = 4;
		slave_cfg.num_outstanding_rd_transactions  = 4;
		slave_cfg.rd_out_of_order_depth = 1;
		slave_cfg.rd_interleave_depth   = 1;
	endfunction : build_phase

	// every AR and R handshake: a beat's bytes run from its first byte to the
	// end of its size-aligned container; count the bytes outside them
	task watch_r();
		int w = int'(master_cfg.bus_width);
		forever
		begin
			@(master_vif.monitor_cb);
			if(master_vif.monitor_cb.arvalid && master_vif.monitor_cb.arready)
				ar_q.push_back('{addr: master_vif.monitor_cb.araddr, size: 1 << master_vif.monitor_cb.arsize, beat: 0});
			if(master_vif.monitor_cb.rvalid && master_vif.monitor_cb.rready && ar_q.size())
			begin
				ar_t            r = ar_q[0];
				ovip_axi_addr_t a = (r.beat == 0) ? r.addr : ((r.addr & ~ovip_axi_addr_t'(r.size - 1)) + r.beat * r.size);
				int             lo = a % w;
				int             hi = (lo & ~(r.size - 1)) + r.size;
				for(int ii = 0; ii < w; ii++)
					if(ii < lo || ii >= hi)
					begin
						n_unused++;
						if(master_vif.monitor_cb.rdata[ii*8 +: 8] != 0) n_unused_nonzero++;
					end
				ar_q[0].beat++;
				if(master_vif.monitor_cb.rlast) void'(ar_q.pop_front());
			end
		end
	endtask : watch_r

	task main_phase(uvm_phase phase);
		ovip_axi_addr_t addr = $urandom_range(20, 1);
		super.main_phase(phase);
		phase.raise_objection(this);
		fork watch_r(); join_none

		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size) + 1))
		begin
			ovip_axi_bytestream_sequence rd_seq = ovip_axi_bytestream_sequence::type_id::create("rd_seq");
			int             n = $urandom_range(400, 64);
			ovip_bytestream fill;
			repeat(n) fill.push_back($urandom);
			mem.write_bytestream(addr, fill);

			rd_seq.tr_type = OVIP_AXI_READ_TRANS;
			rd_seq.addr = addr;
			rd_seq.size = burst_size;
			rd_seq.read_size = n;
			rd_seq.start(master_agent.sqr);

			if(rd_seq.data != fill)
				`uvm_error("UNUSED_RDATA", $sformatf("%s read of %0d bytes at 0x%0x: the master did not get the memory's bytes", burst_size.name(), n, addr))
			else
				`uvm_info("UNUSED_RDATA", $sformatf("%s read of %0d bytes at 0x%0x: the master got the memory's bytes", burst_size.name(), n, addr), UVM_LOW)
			addr += n + $urandom_range(7, 1);   // the next stream starts unaligned too

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		`uvm_info("UNUSED_RDATA", $sformatf("%0d RDATA byte(s) outside their beat's bytes, %0d of them non-zero", n_unused, n_unused_nonzero), UVM_LOW)
		if(n_unused == 0 || n_unused_nonzero == 0)
			`uvm_error("UNUSED_RDATA", "no non-zero byte outside a beat's bytes: randomize_unused_rdata did not act")
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_unused_rdata_test


// The same with auto_byte_lanes_alignment off on both agents: the driver then
// finds each beat's lanes itself
class ovip_axi_unused_rdata_no_auto_align_test extends ovip_axi_unused_rdata_test;
	`uvm_component_utils(ovip_axi_unused_rdata_no_auto_align_test)

	function new(string name = "ovip_axi_unused_rdata_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment  = 0;
	endfunction : build_phase
endclass : ovip_axi_unused_rdata_no_auto_align_test
