// The bytestream sequence in both directions and both burst shapes, on a
// random bus width and alignment mode per seed:
//   1. INCR write with strobe holes under a burst cap (max_len): the memory
//      holds the new bytes where the strobe was on and the old bytes where it
//      was off, no burst is longer than the cap, every BRESP is OKAY. A burst
//      across 4 KiB would be a monitor error.
//   2. INCR read of the same range under a cap: the bytes come back, every
//      beat's RRESP is OKAY.
//   3. FIXED write of a packet to one address: the slave sequence logs the
//      beats it received, and the log is the packet. The memory holds the
//      last beat.
//   4. FIXED read from one address: the bytes there, repeated.
//   5. Four streams at once on the master with mixed timing, one with its data
//      before its address: the W bursts must pair with the AWs in order and
//      every stream's bytes must land where it wrote them.
// ovip_axi_bytestream_lite_test runs 1, 2 and 5 on AXI4-Lite, where every
// burst must be one beat of the bus width whatever the caller asked for.

// A slave sequence that logs the strobed bytes of every FIXED beat per
// address before it writes the memory: what a data register would receive.
class ovip_axi_bytestream_log_slave_seq extends ovip_axi_base_slave_sequence;
	ovip_bytestream fixed_log[ovip_axi_addr_t];
	`uvm_object_utils(ovip_axi_bytestream_log_slave_seq)

	function new(string name = "ovip_axi_bytestream_log_slave_seq");
		super.new(name);
	endfunction

	virtual task write_transaction_to_mem(ovip_axi_trans tr);
		if(tr.burst == OVIP_AXI_BURST_FIXED && tr.resp == OVIP_AXI_RESP_OKAY)
		begin
			int burst_size = 1 << tr.size;
			int valid = burst_size - (tr.addr % burst_size);
			// the first valid byte: lane 0 under auto alignment, the address's bus lane otherwise
			int lane = p_sequencer.cfg.auto_byte_lanes_alignment ? 0 : (tr.addr % tr.bus_width);
			foreach(tr.data_beats[ii])
				for(int bb = 0; bb < valid; bb++)
					if(tr.strb_beats[ii][lane + bb])
						fixed_log[tr.addr].push_back(tr.data_beats[ii][(lane + bb)*8 +: 8]);
		end
		super.write_transaction_to_mem(tr);
	endtask : write_transaction_to_mem
endclass : ovip_axi_bytestream_log_slave_seq


class ovip_axi_bytestream_test extends ovip_axi_base_test;
	ovip_axi_bytestream_log_slave_seq log_seq;
	bit lite = 0;
	int checks = 0;
	`uvm_component_utils(ovip_axi_bytestream_test)

	function new(string name = "ovip_axi_bytestream_test", uvm_component parent);
		super.new(name, parent);
		set_type_override_by_type(ovip_axi_base_slave_sequence::get_type(), ovip_axi_bytestream_log_slave_seq::get_type());
	endfunction : new

	function void build_phase(uvm_phase phase);
		ovip_axi_bus_width_t widths[$] = '{OVIP_AXI_BUS_WIDTH_1B, OVIP_AXI_BUS_WIDTH_2B, OVIP_AXI_BUS_WIDTH_4B, OVIP_AXI_BUS_WIDTH_8B,
		                                   OVIP_AXI_BUS_WIDTH_16B, OVIP_AXI_BUS_WIDTH_32B, OVIP_AXI_BUS_WIDTH_64B, OVIP_AXI_BUS_WIDTH_128B};
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = widths[$urandom_range(widths.size()-1, 0)];
		slave_cfg.bus_width  = master_cfg.bus_width;
		master_cfg.auto_byte_lanes_alignment = $urandom_range(1, 0);
		slave_cfg.auto_byte_lanes_alignment  = $urandom_range(1, 0);

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		master_cfg.num_outstanding_rd_transactions = 20;
		slave_cfg.num_outstanding_transactions     = 20;
		slave_cfg.num_outstanding_wr_transactions  = 20;
		slave_cfg.num_outstanding_rd_transactions  = 20;

		master_cfg.wr_out_of_order_depth      = 1;
		master_cfg.wr_resp_out_of_order_depth = 10;
		master_cfg.wr_interleave_depth        = 1;
		master_cfg.rd_out_of_order_depth      = 10;
		master_cfg.rd_interleave_depth        = 10;
		slave_cfg.wr_out_of_order_depth       = 10;
		slave_cfg.wr_resp_out_of_order_depth  = 10;
		slave_cfg.wr_interleave_depth         = 10;
		slave_cfg.rd_out_of_order_depth       = 10;
		slave_cfg.rd_interleave_depth         = 10;

		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};

		if(!$cast(log_seq, slave_seq)) `uvm_fatal("BYTESTREAM", "the slave sequence is not the logging one")
	endfunction : build_phase

	function void expect_ok(bit ok, string what);
		if(ok) checks++;
		else `uvm_error("BYTESTREAM", what)
	endfunction : expect_ok

	function string bs2string(ovip_bytestream bs);
		string s = "";
		foreach(bs[ii]) s = {s, $sformatf("%02x", bs[ii])};
		return s;
	endfunction : bs2string

	// a random 4 KiB window, so that a stream can cross one or more boundaries
	function ovip_axi_addr_t window();
		return ovip_axi_addr_t'($urandom_range('hfff, 1)) << 12;
	endfunction : window

	// random timing on a sequence: write data before, with or after the address,
	// gaps between beats and bursts, and R/B ready stalls, or none of it
	function void random_timing(ovip_axi_bytestream_sequence seq);
		if($urandom_range(2, 0) == 0) return;   // one in three stays back to back
		seq.max_data_delay = $urandom_range(4, 0);
		seq.max_addr_delay = $urandom_range(4, 0);
		seq.max_addr_phase_delay = $urandom_range(3, 0);
		case($urandom_range(2, 0))
			0: seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
			1: seq.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_SAMPLED;
			2: seq.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;
		endcase
		if($urandom_range(1, 0)) seq.rready_pattern = '{cycles:'{$urandom_range(3, 0), $urandom_range(3, 1)}, loop:1};
		if($urandom_range(1, 0)) seq.bready_pattern = '{cycles:'{$urandom_range(3, 0), $urandom_range(3, 1)}, loop:1};
	endfunction : random_timing

	// the bursts the sequence made: under the cap, Lite one beat of the bus width
	function void check_bursts(ovip_axi_bytestream_sequence seq, int cap, string what);
		int bus = int'(master_cfg.bus_width);
		expect_ok(seq.trans.size() > 0, {what, ": no burst was sent"});
		foreach(seq.trans[ii])
		begin
			ovip_axi_trans tr = seq.trans[ii];
			if(lite)
				expect_ok(tr.len == 0 && (1 << tr.size) == bus,
					$sformatf("%s: burst %0d is len %0d size %0d on a Lite port (one beat of %0d bytes)", what, ii, tr.len, tr.size, bus));
			else
				expect_ok(tr.len <= cap, $sformatf("%s: burst %0d has len %0d, the cap is %0d", what, ii, tr.len, cap));
			if(seq.burst == OVIP_AXI_BURST_FIXED)
				expect_ok(tr.len <= 15, $sformatf("%s: FIXED burst %0d has len %0d", what, ii, tr.len));
			if(tr.tr_type == OVIP_AXI_READ_TRANS)
			begin
				expect_ok(tr.resp_beats.size() == tr.len + 1, $sformatf("%s: burst %0d came back with %0d RRESP for %0d beats", what, ii, tr.resp_beats.size(), tr.len + 1));
				foreach(tr.resp_beats[b])
					expect_ok(tr.resp_beats[b] == OVIP_AXI_RESP_OKAY, $sformatf("%s: burst %0d beat %0d RRESP %s", what, ii, b, tr.resp_beats[b].name()));
			end
		end
		expect_ok(seq.all_okay(), $sformatf("%s: the worst response is %s", what, seq.worst_resp().name()));
	endfunction : check_bursts

	// 1 and 2: an INCR stream with strobe holes under a cap, written and read back
	task incr_round(int round);
		int bus = int'(master_cfg.bus_width);
		int size = lite ? $clog2(bus) : $urandom_range($clog2(bus), 0);
		int n = $urandom_range(3000, 1);
		int cap = lite ? 0 : $urandom_range(40, 0);
		ovip_axi_addr_t addr = window() + (lite ? $urandom_range(100, 0) * bus : $urandom_range(300, 0));
		ovip_bytestream old_bytes, data, expected, after;
		bit strb[$];
		ovip_axi_bytestream_sequence wr, rd;
		string what = $sformatf("INCR round %0d at 0x%0x, %0d bytes, size %0d, cap %0d", round, addr, n, size, cap);

		repeat(n) old_bytes.push_back($urandom);
		mem.write_bytestream(addr, old_bytes);
		repeat(n) begin data.push_back($urandom); strb.push_back($urandom_range(3, 0) != 0); end   // one byte in four is a hole
		foreach(data[ii]) expected.push_back(strb[ii] ? data[ii] : old_bytes[ii]);

		wr = ovip_axi_bytestream_sequence::type_id::create("wr");
		wr.tr_type = OVIP_AXI_WRITE_TRANS;
		wr.addr = addr; wr.size = size; wr.max_len = cap;
		wr.data = data; wr.strb = strb;
		random_timing(wr);
		wr.start(master_agent.sqr);
		check_bursts(wr, cap, {what, " write"});
		after = mem.read_bytestream(addr, n);
		expect_ok(after == expected, $sformatf("%s write: memory\n  expected %s\n  got      %s", what, bs2string(expected), bs2string(after)));

		rd = ovip_axi_bytestream_sequence::type_id::create("rd");
		rd.tr_type = OVIP_AXI_READ_TRANS;
		rd.addr = addr; rd.size = size; rd.max_len = cap; rd.read_size = n;
		random_timing(rd);
		rd.start(master_agent.sqr);
		check_bursts(rd, cap, {what, " read"});
		expect_ok(rd.data.size() == n, $sformatf("%s read: %0d bytes came back", what, rd.data.size()));
		expect_ok(rd.data == expected, $sformatf("%s read: data\n  expected %s\n  got      %s", what, bs2string(expected), bs2string(rd.data)));
	endtask : incr_round

	// 3: a packet into one address
	task fixed_write_round(int round);
		int bus = int'(master_cfg.bus_width);
		int size = $urandom_range($clog2(bus), 0);
		int burst_size = 1 << size;
		ovip_axi_addr_t addr = window() + $urandom_range(100, 0) * burst_size + ($urandom_range(2, 0) == 0 ? $urandom_range(burst_size - 1, 0) : 0);
		int valid = burst_size - (addr % burst_size);
		int n = $urandom_range(400, 1);
		int cap = ($urandom_range(1, 0)) ? $urandom_range(15, 0) : -1;
		int last = (n % valid) ? (n % valid) : valid;
		ovip_bytestream packet, in_mem;
		ovip_axi_bytestream_sequence seq;
		string what = $sformatf("FIXED write round %0d at 0x%0x, %0d bytes, size %0d, cap %0d", round, addr, n, size, cap);

		repeat(n) packet.push_back($urandom);
		seq = ovip_axi_bytestream_sequence::type_id::create("fixed_wr");
		seq.tr_type = OVIP_AXI_WRITE_TRANS;
		seq.burst = OVIP_AXI_BURST_FIXED;
		seq.addr = addr; seq.size = size; seq.max_len = cap; seq.data = packet;
		random_timing(seq);
		seq.start(master_agent.sqr);
		check_bursts(seq, (cap < 0) ? 15 : cap, what);

		expect_ok(log_seq.fixed_log.exists(addr), {what, ": the slave logged no FIXED beat at the address"});
		if(log_seq.fixed_log.exists(addr))
		begin
			expect_ok(log_seq.fixed_log[addr] == packet, $sformatf("%s: the slave received\n  expected %s\n  got      %s", what, bs2string(packet), bs2string(log_seq.fixed_log[addr])));
			log_seq.fixed_log.delete(addr);
		end
		in_mem = mem.read_bytestream(addr, last);
		expect_ok(in_mem == packet[n-last : n-1], $sformatf("%s: the memory holds\n  expected %s (the last beat)\n  got      %s", what, bs2string(packet[n-last : n-1]), bs2string(in_mem)));
	endtask : fixed_write_round

	// 4: a packet out of one address
	task fixed_read_round(int round);
		int bus = int'(master_cfg.bus_width);
		int size = $urandom_range($clog2(bus), 0);
		int burst_size = 1 << size;
		ovip_axi_addr_t addr = window() + $urandom_range(100, 0) * burst_size + ($urandom_range(2, 0) == 0 ? $urandom_range(burst_size - 1, 0) : 0);
		int valid = burst_size - (addr % burst_size);
		int n = $urandom_range(300, 1);
		ovip_bytestream word, expected;
		ovip_axi_bytestream_sequence seq;
		string what = $sformatf("FIXED read round %0d at 0x%0x, %0d bytes, size %0d", round, addr, n, size);

		repeat(valid) word.push_back($urandom);
		mem.write_bytestream(addr, word);
		for(int ii = 0; ii < n; ii++) expected.push_back(word[ii % valid]);

		seq = ovip_axi_bytestream_sequence::type_id::create("fixed_rd");
		seq.tr_type = OVIP_AXI_READ_TRANS;
		seq.burst = OVIP_AXI_BURST_FIXED;
		seq.addr = addr; seq.size = size; seq.read_size = n;
		random_timing(seq);
		seq.start(master_agent.sqr);
		check_bursts(seq, 15, what);
		expect_ok(seq.data == expected, $sformatf("%s: data\n  expected %s\n  got      %s", what, bs2string(expected), bs2string(seq.data)));
	endtask : fixed_read_round

	// 5: four streams at once on the one master, each with its own timing, so
	// a write whose data starts before its address runs beside writes whose
	// data follows the address: the W bursts must still pair with the AWs in
	// order, which the monitor's strobe and WLAST checks watch, and every
	// stream's bytes must land where it wrote them
	task concurrent_round(int round);
		int bus = int'(master_cfg.bus_width);
		ovip_axi_addr_t base = window();
		ovip_bytestream data[4], after;
		string what = $sformatf("concurrent round %0d at 0x%0x", round, base);
		foreach(data[k]) repeat($urandom_range(300, 8)) data[k].push_back($urandom);
		begin
			for(int k = 0; k < 4; k++)
			begin
				automatic int kk = k;
				fork
					begin
						ovip_axi_bytestream_sequence wr = ovip_axi_bytestream_sequence::type_id::create($sformatf("wr%0d", kk));
						wr.tr_type = OVIP_AXI_WRITE_TRANS;
						wr.addr = base + kk * 'h400 + (lite ? 0 : $urandom_range(7, 0));
						wr.size = lite ? $clog2(bus) : $urandom_range($clog2(bus), 0);
						wr.max_len = lite ? 0 : $urandom_range(15, 0);
						wr.id = lite ? 0 : kk;
						wr.data = data[kk];
						random_timing(wr);
						if(kk == 0 && !lite) wr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;   // at least one of each kind
						if(kk == 1) wr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;
						wr.start(master_agent.sqr);
						check_bursts(wr, lite ? 0 : 15, $sformatf("%s stream %0d", what, kk));
						after = mem.read_bytestream(wr.addr, data[kk].size());
						expect_ok(after == data[kk], $sformatf("%s stream %0d: memory\n  expected %s\n  got      %s", what, kk, bs2string(data[kk]), bs2string(after)));
					end
				join_none
			end
			wait fork;   // every stream done, responses included
		end
	endtask : concurrent_round

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);
		`uvm_info("BYTESTREAM", $sformatf("bus %s, auto byte lane alignment master %0d slave %0d%s", master_cfg.bus_width.name(),
			master_cfg.auto_byte_lanes_alignment, slave_cfg.auto_byte_lanes_alignment, lite ? ", AXI4-Lite" : ""), UVM_LOW)
		for(int r = 0; r < 3; r++) incr_round(r);
		if(!lite)
		begin
			for(int r = 0; r < 3; r++) fixed_write_round(r);
			for(int r = 0; r < 3; r++) fixed_read_round(r);
		end
		for(int r = 0; r < 3; r++) concurrent_round(r);
		#100ns;
		`uvm_info("BYTESTREAM", $sformatf("%0d expect_ok(s) passed", checks), UVM_LOW)
		phase.drop_objection(this);
	endtask : main_phase
endclass : ovip_axi_bytestream_test


class ovip_axi_bytestream_lite_test extends ovip_axi_bytestream_test;
	`uvm_component_utils(ovip_axi_bytestream_lite_test)

	function new(string name = "ovip_axi_bytestream_lite_test", uvm_component parent);
		super.new(name, parent);
		lite = 1;
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4_LITE;
		slave_cfg.protocol_type  = OVIP_PROTOCOL_AXI4_LITE;
		master_cfg.bus_width = $urandom_range(1, 0) ? OVIP_AXI_BUS_WIDTH_4B : OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.bus_width  = master_cfg.bus_width;
		master_cfg.wr_resp_out_of_order_depth = 1;
		master_cfg.rd_out_of_order_depth      = 1;
		master_cfg.rd_interleave_depth        = 1;
		slave_cfg.wr_out_of_order_depth       = 1;
		slave_cfg.wr_resp_out_of_order_depth  = 1;
		slave_cfg.wr_interleave_depth         = 1;
		slave_cfg.rd_out_of_order_depth       = 1;
		slave_cfg.rd_interleave_depth         = 1;
	endfunction : build_phase
endclass : ovip_axi_bytestream_lite_test
