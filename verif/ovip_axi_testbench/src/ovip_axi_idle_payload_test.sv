// Verifies cfg.randomize_idle_payload. With it set on both agents, the master
// puts random values on AW, W and AR, and the slave on B and R, while the
// channel's VALID is low. It writes and reads back random bytestreams at every
// burst size and checks two things: the data still round-trips through the
// memory, and every one of the five channels showed a non-zero payload while
// its VALID was low, which none does with the switch off.

class ovip_axi_idle_payload_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_idle_payload_test)

	int n_idle[string];       // cycles a channel's VALID was low
	int n_idle_nonzero[string];   // of them, the ones with a non-zero payload

	function new(string name = "ovip_axi_idle_payload_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		master_cfg.randomize_idle_payload = 1;
		slave_cfg.randomize_idle_payload  = 1;
		master_cfg.num_outstanding_wr_transactions = 4;
		master_cfg.num_outstanding_rd_transactions = 4;
		slave_cfg.num_outstanding_wr_transactions  = 4;
		slave_cfg.num_outstanding_rd_transactions  = 4;
	endfunction : build_phase

	function void count(string ch, bit valid, bit nonzero);
		if(valid) return;
		n_idle[ch]++;
		if(nonzero) n_idle_nonzero[ch]++;
	endfunction : count

	// every cycle out of reset: each channel's payload while its VALID is low
	task watch_idle();
		foreach(n_idle[ch]) n_idle[ch] = 0;
		forever
		begin
			@(master_vif.monitor_cb);
			if(!master_vif.monitor_cb.aresetn) continue;
			count("AW", master_vif.monitor_cb.awvalid, master_vif.monitor_cb.awaddr != 0);
			count("W",  master_vif.monitor_cb.wvalid,  master_vif.monitor_cb.wdata != 0);
			count("AR", master_vif.monitor_cb.arvalid, master_vif.monitor_cb.araddr != 0);
			count("B",  master_vif.monitor_cb.bvalid,  master_vif.monitor_cb.bresp != 0 || master_vif.monitor_cb.bid != 0);
			count("R",  master_vif.monitor_cb.rvalid,  master_vif.monitor_cb.rdata != 0 || master_vif.monitor_cb.rresp != 0);
		end
	endtask : watch_idle

	task main_phase(uvm_phase phase);
		ovip_axi_addr_t addr = $urandom_range(20, 1);
		string          chans[$] = '{"AW", "W", "AR", "B", "R"};
		super.main_phase(phase);
		phase.raise_objection(this);
		foreach(chans[i]) begin n_idle[chans[i]] = 0; n_idle_nonzero[chans[i]] = 0; end
		fork watch_idle(); join_none

		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size) + 1))
		begin
			ovip_axi_bytestream_sequence wr_seq = ovip_axi_bytestream_sequence::type_id::create("wr_seq");
			ovip_axi_bytestream_sequence rd_seq = ovip_axi_bytestream_sequence::type_id::create("rd_seq");
			int n = $urandom_range(400, 64);

			wr_seq.tr_type = OVIP_AXI_WRITE_TRANS;
			wr_seq.addr = addr;
			wr_seq.size = burst_size;
			repeat(n) wr_seq.data.push_back($urandom);
			wr_seq.start(master_agent.sqr);

			rd_seq.tr_type = OVIP_AXI_READ_TRANS;
			rd_seq.addr = addr;
			rd_seq.size = burst_size;
			rd_seq.read_size = n;
			rd_seq.start(master_agent.sqr);

			if(rd_seq.data != wr_seq.data)
				`uvm_error("IDLE_PAYLOAD", $sformatf("%s: %0d bytes at 0x%0x did not read back as written", burst_size.name(), n, addr))
			else
				`uvm_info("IDLE_PAYLOAD", $sformatf("%s: %0d bytes at 0x%0x read back as written", burst_size.name(), n, addr), UVM_LOW)
			addr += n + $urandom_range(7, 1);

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		foreach(chans[i])
		begin
			string ch = chans[i];
			`uvm_info("IDLE_PAYLOAD", $sformatf("%-2s: VALID low %0d cycle(s), %0d of them with a non-zero payload", ch, n_idle[ch], n_idle_nonzero[ch]), UVM_LOW)
			if(n_idle[ch] == 0 || n_idle_nonzero[ch] == 0)
				`uvm_error("IDLE_PAYLOAD", {ch, ": no non-zero payload while VALID was low: randomize_idle_payload did not act"})
		end
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_idle_payload_test
