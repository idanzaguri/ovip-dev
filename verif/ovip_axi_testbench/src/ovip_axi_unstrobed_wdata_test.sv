// Verifies cfg.randomize_unstrobed_wdata. With it set, the master puts a
// random value on every WDATA byte whose WSTRB bit is low. For every burst
// size it writes a random bytestream at an unaligned address with random
// strobe holes, then checks two things: the slave's memory took exactly the
// strobed bytes and kept its old value under every low strobe, and the bus
// carried non-zero bytes under low strobes, which it never does with the
// switch off.

class ovip_axi_unstrobed_wdata_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_unstrobed_wdata_test)

	int n_low;           // WDATA bytes seen on the bus with WSTRB low
	int n_low_nonzero;   // of them, the ones that were not zero

	function new(string name = "ovip_axi_unstrobed_wdata_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		master_cfg.randomize_unstrobed_wdata = 1;
		master_cfg.num_outstanding_wr_transactions = 4;
		master_cfg.num_outstanding_rd_transactions = 4;
		slave_cfg.num_outstanding_wr_transactions  = 4;
		slave_cfg.num_outstanding_rd_transactions  = 4;
	endfunction : build_phase

	// every W handshake: count the bytes whose strobe is low, and the non-zero ones
	task watch_w();
		forever
		begin
			@(master_vif.monitor_cb);
			if(master_vif.monitor_cb.wvalid && master_vif.monitor_cb.wready)
				for(int ii = 0; ii < int'(master_cfg.bus_width); ii++)
					if(!master_vif.monitor_cb.wstrb[ii])
					begin
						n_low++;
						if(master_vif.monitor_cb.wdata[ii*8 +: 8] != 0) n_low_nonzero++;
					end
		end
	endtask : watch_w

	task main_phase(uvm_phase phase);
		ovip_axi_addr_t addr = $urandom_range(20, 1);
		super.main_phase(phase);
		phase.raise_objection(this);
		fork watch_w(); join_none

		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size) + 1))
		begin
			ovip_axi_bytestream_sequence wr_seq = ovip_axi_bytestream_sequence::type_id::create("wr_seq");
			int             n = $urandom_range(400, 64);
			ovip_bytestream old_bytes = mem.read_bytestream(addr, n), got;
			ovip_bytestream expected;

			wr_seq.tr_type = OVIP_AXI_WRITE_TRANS;
			wr_seq.addr = addr;
			wr_seq.size = burst_size;
			for(int ii = 0; ii < n; ii++)
			begin
				bit on = ($urandom_range(3, 0) != 0);   // about one byte in four is a strobe hole
				wr_seq.data.push_back($urandom);
				wr_seq.strb.push_back(on);
				expected.push_back(on ? wr_seq.data[ii] : old_bytes[ii]);
			end
			wr_seq.start(master_agent.sqr);

			got = mem.read_bytestream(addr, n);
			if(got != expected)
				`uvm_error("UNSTROBED_WDATA", $sformatf("%s write of %0d bytes at 0x%0x: the memory does not hold the strobed bytes alone", burst_size.name(), n, addr))
			else
				`uvm_info("UNSTROBED_WDATA", $sformatf("%s write of %0d bytes at 0x%0x: the memory holds the strobed bytes alone", burst_size.name(), n, addr), UVM_LOW)
			addr += n + $urandom_range(7, 1);   // the next stream starts unaligned too

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		`uvm_info("UNSTROBED_WDATA", $sformatf("%0d WDATA byte(s) under a low strobe, %0d of them non-zero", n_low, n_low_nonzero), UVM_LOW)
		if(n_low == 0 || n_low_nonzero == 0)
			`uvm_error("UNSTROBED_WDATA", "no non-zero byte under a low strobe: randomize_unstrobed_wdata did not act")
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_unstrobed_wdata_test
