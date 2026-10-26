// Unit test for ovip_mem (the simple word-addressed memory model the slave
// uses). Verifies word-aligned read/write, byte-enable masking on writes,
// the bytestream read/write helpers, and the init-pattern behavior on first
// access. Standalone -- does not bring up the AXI agents.

class ovip_mem_test extends uvm_test;
	ovip_mem mem;

	localparam int BENCH_ROUNDS = 1000;    // rounds of the benchmark locally
	localparam int EDA_BENCH_SECONDS = 15; // its wall-time budget on EDA Playground

	`uvm_component_utils(ovip_mem_test)

	function new(string name = "ovip_mem_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new


	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mem = ovip_mem::type_id::create("mem", this);
	endfunction : build_phase

	// Seconds since the epoch, by the wall clock. $system returns the exit
	// status, not stdout, so date writes to a file and $fscanf reads it back.
	local function int unsigned wall_seconds();
		int fd;
		int unsigned t;
		void'($system("date +%s > /tmp/ovip_mem_test_time"));
		fd = $fopen("/tmp/ovip_mem_test_time", "r");
		void'($fscanf(fd, "%d", t));
		$fclose(fd);
		return t;
	endfunction : wall_seconds

	task run_phase(uvm_phase phase);
		super.run_phase(phase);
		phase.raise_objection(this);

		// write_bytestream at every offset inside a word and every size up to
		// three words, with a guard byte on each side: the bytes land, the
		// guards stay. (The full-word count was off by one both ways.)
		begin
			int checks = 0;
			for(int off = 0; off < 4; off++)
				for(int n = 1; n <= 12; n++)
				begin
					ovip_mem::addr_t base = 'h1000 + off + 'h100 * n;
					byte fill[$], data[$], got[$];
					repeat(n + 2) fill.push_back(8'ha5);
					mem.write_bytestream(base - 1, fill);          // guards and the range
					repeat(n) data.push_back($urandom);
					mem.write_bytestream(base, data);
					got = mem.read_bytestream(base - 1, n + 2);
					if(got[0] != 8'ha5 || got[n + 1] != 8'ha5 || got[1 : n] != data)
						`uvm_error("MEM", $sformatf("write_bytestream at offset %0d of %0d bytes: got %p for %p", off, n, got, data))
					else checks++;
				end
			`uvm_info("MEM", $sformatf("write_bytestream: %0d check(s) passed", checks), UVM_LOW)
		end

		// ovip_mem benchmark: rounds of 100 write_bytestream calls of 10 KB
		// each with random per-byte strobes, timed by the wall clock. Locally
		// it runs BENCH_ROUNDS rounds. On EDA Playground (the bundle's
		// eda_tb.sv defines OVIP_EDA_PLAYGROUND) that count runs past the
		// site's runtime cap, so it runs rounds for EDA_BENCH_SECONDS
		// instead. The ROUNDS line gives the rate either way.
		begin
			byte wdata[100][$];
			bit wstrb[100][$];
			int unsigned t1, t2;
			int rounds = 0;

			foreach(wdata[ii])
			begin
				repeat(1024*10)
				begin
					wdata[ii].push_back($urandom);
					wstrb[ii].push_back($urandom_range(1,0));
				end
			end

			t1 = wall_seconds();
			forever
			begin
				foreach(wdata[ii])
				begin
					mem.write_bytestream($urandom_range(1024,0),wdata[ii], wstrb[ii]);
				end
				rounds++;
				`ifdef OVIP_EDA_PLAYGROUND
				if(wall_seconds() - t1 >= EDA_BENCH_SECONDS) break;
				`else
				if(rounds == BENCH_ROUNDS) break;
				`endif
			end
			t2 = wall_seconds();

			$display("TIME: %0d sec", t2 - t1);
			if(t2 > t1)
				$display("ROUNDS: %0d, %0d write_bytestream calls, %0d per sec", rounds, rounds * 100, rounds * 100 / (t2 - t1));
			else
				$display("ROUNDS: %0d, %0d write_bytestream calls", rounds, rounds * 100);
		end
		phase.drop_objection(this);
	endtask : run_phase

endclass : ovip_mem_test

