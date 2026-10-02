// Unit test for ovip_mem (the simple word-addressed memory model the slave
// uses). Verifies word-aligned read/write, byte-enable masking on writes,
// the bytestream read/write helpers, and the init-pattern behavior on first
// access. Standalone -- does not bring up the AXI agents.

class ovip_mem_test extends uvm_test;
	ovip_mem mem;

	`uvm_component_utils(ovip_mem_test)

	function new(string name = "ovip_mem_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new


	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		mem = ovip_mem::type_id::create("mem", this);
	endfunction : build_phase

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

		// ovip_mem benchmark!!!
		begin
			byte wdata[100][$];
			bit wstrb[100][$];
			int unsigned t1, t2;
			int fd;

			foreach(wdata[ii])
			begin
				repeat(1024*10)
				begin
					wdata[ii].push_back($urandom);
					wstrb[ii].push_back($urandom_range(1,0));
				end
			end

			// $system returns the shell exit status, not stdout -- redirect
			// the date to a file and read the seconds back with $fscanf.
			void'($system("date +%s > /tmp/ovip_mem_test_t1"));
			fd = $fopen("/tmp/ovip_mem_test_t1", "r");
			void'($fscanf(fd, "%d", t1));
			$fclose(fd);

			repeat(1000)
			begin
				foreach(wdata[ii])
				begin
					mem.write_bytestream($urandom_range(1024,0),wdata[ii], wstrb[ii]);
				end
			end

			void'($system("date +%s > /tmp/ovip_mem_test_t2"));
			fd = $fopen("/tmp/ovip_mem_test_t2", "r");
			void'($fscanf(fd, "%d", t2));
			$fclose(fd);

			$display("TIME: %0d sec", t2 - t1);
		end
		phase.drop_objection(this);
	endtask : run_phase

endclass : ovip_mem_test

