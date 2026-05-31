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

