// Unit test for ovip_mem_space, the memory built from memories with an
// address map. Standalone, no AXI agents. Checks the three ways a region
// maps to a sub (the system address, the offset, packed), an alias, a
// striped region, accesses that cross a map boundary, the word helpers, the
// random fill, the compare, and the refusal of a hole.

class ovip_mem_space_hole_catcher extends uvm_report_catcher;
	int caught;
	function new(string name = "ovip_mem_space_hole_catcher");
		super.new(name);
	endfunction
	function action_e catch();
		if (get_id() == "MEM_SPACE/HOLE") begin caught++; return CAUGHT; end
		return THROW;
	endfunction
endclass : ovip_mem_space_hole_catcher


class ovip_mem_space_test extends uvm_test;
	typedef ovip_mem_space::addr_t addr_t;

	ovip_mem       a, b, c, d, s[4];
	ovip_mem_space space;
	int ia, ib, ic, id, is[4];
	// the shadow (same map, fresh subs) and an untouched space, for compare;
	// components, so they are built in build_phase like everything else
	ovip_mem       a2, b2, c2, d2, s2[4], e[8];
	ovip_mem_space shadow, empty;
	int checks;

	`uvm_component_utils(ovip_mem_space_test)

	function new(string name = "ovip_mem_space_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		a = ovip_mem::type_id::create("a", this);
		b = ovip_mem::type_id::create("b", this);
		c = ovip_mem::type_id::create("c", this);
		d = ovip_mem::type_id::create("d", this);
		foreach (s[i]) s[i] = ovip_mem::type_id::create($sformatf("s%0d", i), this);
		space = ovip_mem_space::type_id::create("space", this);
		a2 = ovip_mem::type_id::create("a2", this); b2 = ovip_mem::type_id::create("b2", this);
		c2 = ovip_mem::type_id::create("c2", this); d2 = ovip_mem::type_id::create("d2", this);
		foreach (s2[i]) s2[i] = ovip_mem::type_id::create($sformatf("s2_%0d", i), this);
		foreach (e[i])  e[i]  = ovip_mem::type_id::create($sformatf("e%0d", i), this);
		shadow = ovip_mem_space::type_id::create("shadow", this);
		empty  = ovip_mem_space::type_id::create("empty", this);
	endfunction : build_phase

	// A byte that depends on its system address, so a misplaced byte shows.
	function byte pat(addr_t addr);
		return byte'(addr[7:0] ^ addr[15:8] ^ 8'h5A);
	endfunction

	function ovip_bytestream pattern(addr_t addr, int size);
		ovip_bytestream q;
		for (int i = 0; i < size; i++) q.push_back(pat(addr + i));
		return q;
	endfunction

	function void expect_ok(bit ok, string what);
		checks++;
		if (!ok) `uvm_error("MEM_SPACE_TEST", what)
	endfunction

	function void build_map(ovip_mem_space sp, ovip_mem ma, ovip_mem mb, ovip_mem mc, ovip_mem md, ovip_mem ms[4], output int xa, output int xb, output int xc, output int xd, output int xs[4]);
		int stripe[$];
		xa = sp.add_sub(ma, "A"); xb = sp.add_sub(mb, "B"); xc = sp.add_sub(mc, "C"); xd = sp.add_sub(md, "D");
		foreach (ms[i]) begin xs[i] = sp.add_sub(ms[i]); stripe.push_back(xs[i]); end
		sp.add_region("ram",    'h1000, 'h1000, xa, 'h1000);   // A sees the system address
		sp.add_region("ram2",   'h2000, 'h1000, xd, 0);        // D sees the offset; contiguous with ram
		sp.add_region("alias0", 'h8000, 'h100,  xb, 0);        // two system ranges on B's first 256 bytes
		sp.add_region("alias1", 'h9000, 'h100,  xb, 0);
		sp.add_region("cmp0",   'hA000, 'h200,  xc, 0);        // C's regions packed back to back
		sp.add_region("cmp1",   'hC000, 'h100,  xc, 'h200);
		sp.add_striped_region("ddr", 'h10000, 'h1000, stripe, 512);
	endfunction

	task run_phase(uvm_phase phase);
		super.run_phase(phase);
		phase.raise_objection(this);
		build_map(space, a, b, c, d, s, ia, ib, ic, id, is);
		`uvm_info("MEM_SPACE_TEST", {"the map:\n", space.map2string()}, UVM_LOW)

		// resolve, covers
		begin
			int sub; addr_t sa, run;
			expect_ok(space.num_regions() == 7, "7 regions");
			expect_ok(space.resolve('h1234, sub, sa, run) && sub == ia && sa == 'h1234 && run == 'h1000 - 'h234, "resolve inside ram");
			expect_ok(space.resolve('h2010, sub, sa, run) && sub == id && sa == 'h10 && run == 'hFF0, "resolve inside ram2 (offset view)");
			expect_ok(!space.resolve('h3000, sub, sa, run), "0x3000 is a hole");
			expect_ok(space.resolve('hC010, sub, sa, run) && sub == ic && sa == 'h210, "resolve inside cmp1 (packed view)");
			expect_ok(space.resolve('h10000 + 512*5 + 7, sub, sa, run) && sub == is[1] && sa == 512 + 7 && run == 512 - 7, "resolve chunk 5 of the stripe");
			expect_ok(space.covers('h1FF8, 16), "ram + ram2 cover 0x1FF8..0x2007");
			expect_ok(!space.covers('h2FF8, 16), "0x2FF8..0x3007 runs into the hole");
		end

		// a write that crosses from ram (A) into ram2 (D)
		begin
			ovip_bytestream w = pattern('h1FF8, 16), r;
			space.write_bytestream('h1FF8, w);
			r = a.read_bytestream('h1FF8, 8); expect_ok(r == w[0:7],  "A holds the first 8 bytes at its own address");
			r = d.read_bytestream(0, 8);      expect_ok(r == w[8:15], "D holds the last 8 bytes at offset 0");
			r = space.read_bytestream('h1FF8, 16); expect_ok(r == w, "the parent gathers the 16 bytes back");
		end

		// an alias: two system ranges on the same B bytes
		begin
			ovip_bytestream w = pattern('h8010, 4), r;
			space.write_bytestream('h8010, w);
			r = space.read_bytestream('h9010, 4); expect_ok(r == w, "written through alias0, read back through alias1");
			r = b.read_bytestream('h10, 4);       expect_ok(r == w, "B holds it at offset 0x10");
		end

		// the packed view
		begin
			ovip_bytestream w = pattern('hC010, 4), r;
			space.write_bytestream('hC010, w);
			r = c.read_bytestream('h210, 4); expect_ok(r == w, "cmp1 lands on C after cmp0's 0x200 bytes");
		end

		// the striped region: 4 KiB over four subs, 512 bytes a chunk
		begin
			ovip_bytestream w = pattern('h10000, 'h1000), r;
			space.write_bytestream('h10000, w);
			foreach (s[k])
				for (int cc = 0; cc < 2; cc++)
				begin
					int chunk = 4*cc + k;
					r = s[k].read_bytestream(cc*512, 512);
					expect_ok(r == w[chunk*512 : chunk*512 + 511], $sformatf("sub %0d holds chunk %0d at its offset %0d", k, chunk, cc*512));
				end
			r = space.read_bytestream('h10000, 'h1000); expect_ok(r == w, "the parent gathers the 4 KiB in order");
			r = space.read_bytestream('h10000 + 512 - 32, 64); expect_ok(r == w[512-32 : 512+31], "a read across a chunk boundary");
		end

		// the word helpers, across the ram/ram2 boundary, with byte enables
		begin
			ovip_bytestream r;
			space.write('h1FFE, 32'h11223344);
			expect_ok(space.read('h1FFE) == 32'h11223344, "word read back across the boundary");
			r = a.read_bytestream('h1FFE, 2); expect_ok(r[0] == 8'h44 && r[1] == 8'h33, "A got the low two bytes");
			r = d.read_bytestream(0, 2);      expect_ok(r[0] == 8'h22 && r[1] == 8'h11, "D got the high two bytes");
			space.write('h1FFE, 32'hAABBCCDD, 4'b0101);
			expect_ok(space.read('h1FFE) == 32'h11BB33DD, "byte enables keep bytes 1 and 3");
		end

		// a random fill reads back the same twice, and lives in the sub
		begin
			ovip_bytestream r1, r2, r3;
			space.fill_random('hA000, 64);
			r1 = space.read_bytestream('hA000, 64);
			r2 = space.read_bytestream('hA000, 64);
			r3 = c.read_bytestream(0, 64);
			expect_ok(r1 == r2 && r1 == r3 && r1.size() == 64, "fill_random is stable and lands on C");
		end

		// compare against a shadow with the same map
		begin
			int xa, xb, xc, xd, xs[4];
			int lines = 0;
			build_map(shadow, a2, b2, c2, d2, s2, xa, xb, xc, xd, xs);
			for (int i = 0; i < space.num_regions(); i++)
			begin
				ovip_mem_space::region_t rg = space.get_region(i);
				ovip_bytestream w = space.read_bytestream(rg.base, int'(rg.size));
				shadow.write_bytestream(rg.base, w);
			end
			expect_ok(space.compare(shadow) == 0, "a copy compares equal");
			begin
				ovip_bytestream one = '{8'hFF};
				shadow.write_bytestream('h1010, one);
				expect_ok(space.compare(shadow, "poked", 0) == 1, "one changed byte is one mismatch");
			end
			foreach (e[i]) void'(empty.add_sub(e[i]));
			foreach (space.subs[i]) lines += space.subs[i].num_lines();
			expect_ok(space.compare(empty, "empty", 0) == lines, "every touched line is a mismatch against an untouched space");
		end

		// a hole is refused, with nothing done
		begin
			ovip_mem_space_hole_catcher catcher = new();
			ovip_bytestream w = pattern('h3000, 4), r;
			uvm_report_cb::add(null, catcher);
			space.write_bytestream('h3000, w);
			r = space.read_bytestream('h2FFE, 4);
			uvm_report_cb::delete(null, catcher);
			expect_ok(catcher.caught == 2, "a write into a hole and a read across one each report MEM_SPACE/HOLE");
			expect_ok(r.size() == 0, "the refused read returns nothing");
		end

		`uvm_info("MEM_SPACE_TEST", $sformatf("%0d checks", checks), UVM_LOW)
		phase.drop_objection(this);
	endtask : run_phase
endclass : ovip_mem_space_test
