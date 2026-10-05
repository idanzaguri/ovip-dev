// Verifies cfg.awready_waits_for_wvalid. With it set, the slave asserts
// AWREADY only while a write burst has offered WVALID ahead of its AW. At
// every burst size the master writes two random bytestreams, one with W after
// the address and one with W before it, with gaps, and reads them back. The
// test checks three things: the data round-trips, the slave never took an AW
// before its burst had offered WVALID, and some AW did wait for its W.

class ovip_axi_awready_waits_for_wvalid_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_awready_waits_for_wvalid_test)

	int n_aw;          // AW handshakes
	int n_aw_early;    // of them, taken before their burst offered WVALID: must stay 0
	int n_aw_wait;     // cycles AWVALID was high and AWREADY low

	function new(string name = "ovip_axi_awready_waits_for_wvalid_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		slave_cfg.awready_waits_for_wvalid = 1;
		master_cfg.num_outstanding_wr_transactions = 4;
		master_cfg.num_outstanding_rd_transactions = 4;
		slave_cfg.num_outstanding_wr_transactions  = 4;
		slave_cfg.num_outstanding_rd_transactions  = 4;
	endfunction : build_phase

	// every edge: the W bursts that offered WVALID, against the AWs taken
	task watch_aw();
		int w_ahead  = 0;
		bit in_burst = 0;
		forever
		begin
			@(master_vif.monitor_cb);
			if(!master_vif.monitor_cb.aresetn) continue;
			if(master_vif.monitor_cb.wvalid && !in_burst) begin w_ahead++; in_burst = 1; end
			if(master_vif.monitor_cb.wvalid && master_vif.monitor_cb.wready && master_vif.monitor_cb.wlast) in_burst = 0;
			if(master_vif.monitor_cb.awvalid && !master_vif.monitor_cb.awready) n_aw_wait++;
			if(master_vif.monitor_cb.awvalid && master_vif.monitor_cb.awready)
			begin
				n_aw++;
				if(w_ahead <= 0) n_aw_early++;
				w_ahead--;
			end
		end
	endtask : watch_aw

	task main_phase(uvm_phase phase);
		ovip_axi_addr_t addr = $urandom_range(20, 1);
		super.main_phase(phase);
		phase.raise_objection(this);
		fork watch_aw(); join_none

		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size) + 1))
		begin
			ovip_axi_bytestream_sequence rd_seq = ovip_axi_bytestream_sequence::type_id::create("rd_seq");
			ovip_bytestream written;
			int n = 0;

			// two writes: W after the address (with a gap), then W before it. A
			// master may never wait for AWREADY before WVALID, so not ADDR_SAMPLED
			for(int k = 0; k < 2; k++)
			begin
				ovip_axi_bytestream_sequence wr_seq = ovip_axi_bytestream_sequence::type_id::create("wr_seq");
				int m = $urandom_range(200, 32);
				wr_seq.tr_type = OVIP_AXI_WRITE_TRANS;
				wr_seq.addr = addr + n;
				wr_seq.size = burst_size;
				repeat(m) wr_seq.data.push_back($urandom);
				wr_seq.data_start_event = (k == 0) ? OVIP_AXI_DATA_START_EV_ADDR_DRIVEN : OVIP_AXI_DATA_START_EV_BEFORE_ADDR;
				wr_seq.max_data_delay = 4;
				wr_seq.start(master_agent.sqr);
				written = {written, wr_seq.data};
				n += m;
			end

			rd_seq.tr_type = OVIP_AXI_READ_TRANS;
			rd_seq.addr = addr;
			rd_seq.size = burst_size;
			rd_seq.read_size = n;
			rd_seq.start(master_agent.sqr);

			if(rd_seq.data != written)
				`uvm_error("AW_WAITS_FOR_W", $sformatf("%s: %0d bytes at 0x%0x did not read back as written", burst_size.name(), n, addr))
			else
				`uvm_info("AW_WAITS_FOR_W", $sformatf("%s: %0d bytes at 0x%0x read back as written", burst_size.name(), n, addr), UVM_LOW)
			addr += n + $urandom_range(7, 1);

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		`uvm_info("AW_WAITS_FOR_W", $sformatf("%0d AW handshake(s), %0d before their burst offered WVALID; AWVALID waited %0d cycle(s) for AWREADY",
			n_aw, n_aw_early, n_aw_wait), UVM_LOW)
		if(n_aw == 0 || n_aw_early != 0)
			`uvm_error("AW_WAITS_FOR_W", "the slave took an AW before its burst offered WVALID")
		if(n_aw_wait == 0)
			`uvm_error("AW_WAITS_FOR_W", "no AW ever waited for its W: awready_waits_for_wvalid did not act")
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_awready_waits_for_wvalid_test
