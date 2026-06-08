// Verifies end-to-end data integrity across every bus width and burst size
// combination. For each iteration: build a random byte stream, push it
// through the master via the bytestream sequence at varying burst sizes,
// read back through both the memory backdoor and a frontdoor read sequence,
// and compare byte-for-byte. The 22 subclasses below specialize this base
// for each (bus_width, auto_byte_lanes_alignment) combination so the
// regression covers the full grid.

class ovip_axi_data_integrity_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_data_integrity_test)

	function new(string name = "ovip_axi_data_integrity_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;

		master_cfg.num_outstanding_transactions    = 50;
		master_cfg.num_outstanding_wr_transactions = 20;
		master_cfg.num_outstanding_rd_transactions = 20;

		slave_cfg.num_outstanding_transactions    = 20;
		slave_cfg.num_outstanding_wr_transactions = 20;
		slave_cfg.num_outstanding_rd_transactions = 20;

		master_cfg.wr_out_of_order_depth = 1; // must be one for MASTER & AXI4
		master_cfg.wr_resp_out_of_order_depth = 10;
		master_cfg.wr_interleave_depth = 1;
		master_cfg.rd_out_of_order_depth = 10;
		master_cfg.rd_interleave_depth = 10;

		slave_cfg.wr_out_of_order_depth = 10;
		slave_cfg.wr_resp_out_of_order_depth = 10;
		slave_cfg.wr_interleave_depth = 10;
		slave_cfg.rd_out_of_order_depth = 10;
		slave_cfg.rd_interleave_depth = 10;

		master_cfg.auto_byte_lanes_alignment = 1;
		slave_cfg.auto_byte_lanes_alignment = 1;

		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};
	endfunction : build_phase

	function string bytestream2string(ovip_bytestream bs);
		string str = "";
		foreach(bs[ii]) str = $sformatf("%x%s",bs[ii],str);
		return str;
	endfunction : bytestream2string

	task main_phase(uvm_phase phase);
		ovip_bytestream wr_data;
		ovip_bytestream rd_data;
		ovip_axi_addr_t start_addr = $urandom_range(20,0);
		ovip_axi_addr_t addr;
		int chunk_size[$];
		int ptr; // running byte offset into wr_data for the front-door read

		super.main_phase(phase);
		phase.raise_objection(this);


		addr = start_addr;
		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size)+1))
		begin
			ovip_axi_bytestream_sequence wr_seq = ovip_axi_bytestream_sequence::type_id::create("wr_seq");
			chunk_size.push_back( $urandom_range(15000, 300) );
			begin
				repeat(chunk_size[$]) wr_data.push_back($urandom);
				// for easy debug:
				//ptr++;
				//repeat(chunk_size[$]) void'(wr_data.pop_back()); // tp keep random the same....
				//repeat(4) wr_data.push_back(ptr);
				//repeat(chunk_size[$]-8) wr_data.push_back(0);
				//repeat(4) wr_data.push_back(ptr);
			end
			`uvm_info("data_integ_check", $sformatf("WR addr=0x%0x size=%0d (%s)",addr,chunk_size[$], burst_size.name()), UVM_LOW)

			wr_seq.tr_type = OVIP_AXI_WRITE_TRANS;
			wr_seq.addr = addr;
			wr_seq.size = burst_size;
			wr_seq.data = wr_data[int'(addr-start_addr) : int'(addr-start_addr)+chunk_size[$]-1];
			wr_seq.start(master_agent.sqr);
			addr += chunk_size[$];

			rd_data = mem.read_bytestream(wr_seq.addr, wr_seq.data.size());
			if(wr_seq.data != rd_data)
			begin
				mem.print();
				`uvm_info("data_integ_check",$sformatf("WR:(%0d) %s",wr_seq.data.size(), bytestream2string(wr_seq.data)),UVM_LOW)
				`uvm_info("data_integ_check",$sformatf("RD:(%0d) %s",rd_data.size(), bytestream2string(rd_data)),UVM_LOW)
				`uvm_fatal("data_integ_check","mem backdoor RD failed")
			end
			else
				`uvm_info("data_integ_check","mem backdoor RD passes",UVM_LOW)

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		rd_data = mem.read_bytestream(start_addr, wr_data.size());
		if(wr_data != rd_data)
		begin
			`uvm_info("data_integ_check",$sformatf("WR:(%0d) %s",wr_data.size(), bytestream2string(wr_data)),UVM_LOW)
			`uvm_info("data_integ_check",$sformatf("RD:(%0d) %s",rd_data.size(), bytestream2string(rd_data)),UVM_LOW)
			`uvm_error("data_integ_check","final mem backdoor read failed!!!")
		end



		//
		// READ
		//
		rd_data = {};
		ptr = 0;
		addr = start_addr;
		for(ovip_axi_size_t burst_size = OVIP_AXI_SIZE_1B; 1; burst_size = ovip_axi_size_t'(int'(burst_size)+1))
		begin
			int op;
			ovip_bytestream __wr;

			ovip_axi_bytestream_sequence rd_seq = ovip_axi_bytestream_sequence::type_id::create("rd_seq");
			`uvm_info("data_integ_check", $sformatf("RD addr=0x%x size=%0d (%s)",addr,chunk_size[0], burst_size.name()), UVM_LOW)
			rd_seq.tr_type = OVIP_AXI_READ_TRANS;
			rd_seq.addr = addr;
			rd_seq.size = burst_size;
			rd_seq.read_size = chunk_size[0];
			rd_seq.start(master_agent.sqr);
			rd_data = {rd_data, rd_seq.data};

			if(rd_seq.read_size != rd_seq.data.size()) `uvm_fatal("bytestrea seq mismatch",$sformatf("EXP:%0d ACT:%0d",rd_seq.read_size, rd_seq.data.size()))

			__wr =  wr_data[ptr : ptr+rd_seq.data.size()-1];
			if(rd_seq.data != __wr)
			begin
				`uvm_info("data_integ_check",$sformatf("WR:(%0d) %s",__wr.size(), bytestream2string(__wr)),UVM_LOW)
				`uvm_info("data_integ_check",$sformatf("RD:(%0d) %s",rd_seq.data.size(), bytestream2string(rd_seq.data)),UVM_LOW)
				`uvm_fatal("data_integ_check","frontdoor read failed!!!")
			end

			addr += chunk_size[0];
			ptr += chunk_size[0];
			//op = chunk_size.pop_back();
			chunk_size.delete(0);

			if(burst_size == ovip_axi_size_t'($clog2(master_cfg.bus_width))) break;
		end

		if(wr_data != rd_data)
		begin
			`uvm_info("data_integ_check",$sformatf("WR:(%0d) %s",wr_data.size(), bytestream2string(wr_data)),UVM_LOW)
			`uvm_info("data_integ_check",$sformatf("RD:(%0d) %s",rd_data.size(), bytestream2string(rd_data)),UVM_LOW)
			`uvm_error("data_integ_check","final frontdoor read failed!!!")
		end

		#10ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass


class ovip_axi_data_integrity_1B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_1B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_1B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_1B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_1B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_2B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_2B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_2B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_2B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_2B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_4B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_4B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_4B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_4B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_4B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_8B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_8B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_8B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_16B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_16B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_16B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_16B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_16B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_32B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_32B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_32B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_32B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_32B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_64B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_64B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_64B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_64B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_64B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_128B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_128B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_128B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_128B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_128B;
	endfunction : build_phase
endclass

// Out-of-spec widths: AxSIZE encoding > 3'b111 requires size_width = 4 (auto-bumped in check_config).
class ovip_axi_data_integrity_256B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_256B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_256B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_256B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_256B;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_512B_bus_width_test extends ovip_axi_data_integrity_test;
	`uvm_component_utils(ovip_axi_data_integrity_512B_bus_width_test)
	function new(string name = "ovip_axi_data_integrity_512B_bus_width_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_512B;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_512B;
	endfunction : build_phase
endclass


/////////////////////////////////////////


class ovip_axi_data_integrity_1B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_1B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_1B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_1B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_2B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_2B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_2B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_2B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_4B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_4B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_4B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_4B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_8B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_8B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_8B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_8B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_16B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_16B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_16B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_16B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_32B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_32B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_32B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_32B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_64B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_64B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_64B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_64B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_128B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_128B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_128B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_128B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_256B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_256B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_256B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_256B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass

class ovip_axi_data_integrity_512B_bus_width_no_auto_align_test extends ovip_axi_data_integrity_512B_bus_width_test;
	`uvm_component_utils(ovip_axi_data_integrity_512B_bus_width_no_auto_align_test)
	function new(string name = "ovip_axi_data_integrity_512B_bus_width_no_auto_align_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 0;
		slave_cfg.auto_byte_lanes_alignment = 0;
	endfunction : build_phase
endclass
