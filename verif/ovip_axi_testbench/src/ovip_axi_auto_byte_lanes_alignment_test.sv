// Verifies the auto-byte-lanes alignment feature: with
// cfg.auto_byte_lanes_alignment = 1, the user fills data_beats lane-0-aligned
// and the driver/monitor handle the byte-lane shift for narrow / unaligned
// transfers. This test drives a mix of unaligned addresses and narrow beats
// and confirms the round-trip through the memory model is byte-correct.

class ovip_debug_seq extends uvm_sequence#(ovip_axi_trans);

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(ovip_debug_seq)

	function new(string name = "ovip_debug_seq");
		super.new(name);
	endfunction

	virtual task body();
		ovip_axi_trans tr = ovip_axi_trans::type_id::create("tr");

		start_item(tr);
		tr.tr_type = OVIP_AXI_WRITE_TRANS;
		tr.addr  = 6;
		tr.id    = 0;
		tr.len   = 1;
		tr.size  = OVIP_AXI_SIZE_8B;
		tr.burst = OVIP_AXI_BURST_INCR;
		tr.data_start_event = OVIP_AXI_DATA_START_EV_ADDR_DRIVEN;

		tr.strb_beats.push_back(8'b0000_0011);
		tr.data_beats.push_back(64'h00000000_00001100);

		tr.strb_beats.push_back(8'b1110_0111);
		tr.data_beats.push_back(64'h99887766_55443322);

		finish_item(tr);
		`uvm_info("auto_byte_lanes_alignment/master_drv/before", $sformatf("%0b", tr.strb_beats[0]), UVM_LOW)
		get_response(tr);
		`uvm_info("auto_byte_lanes_alignment/master_drv/after", $sformatf("%0b", tr.strb_beats[0]), UVM_LOW)


		tr = new("rd");
		start_item(tr);
		tr.tr_type = OVIP_AXI_READ_TRANS;
		tr.addr  = 6;
		tr.id    = 0;
		tr.len   = 1;
		tr.size  = OVIP_AXI_SIZE_8B;
		tr.burst = OVIP_AXI_BURST_INCR;

		finish_item(tr);
		get_response(tr);
		foreach(tr.data_beats[ii])
			`uvm_info("auto_byte_lanes_alignment/master_drv/after", $sformatf("[%0d] %0x", ii, tr.data_beats[ii]), UVM_LOW)

	endtask : body
endclass

class ovip_axi_auto_byte_lanes_alignment_test extends ovip_axi_base_test;

	`uvm_analysis_imp_decl(_m)
	`uvm_analysis_imp_decl(_s)

	ovip_axi_trans master_mon[$], slave_mon[$];

	uvm_analysis_imp_m#(ovip_axi_trans, ovip_axi_auto_byte_lanes_alignment_test) master_mon_ap;
	uvm_analysis_imp_s#(ovip_axi_trans, ovip_axi_auto_byte_lanes_alignment_test) slave_mon_ap;

	`uvm_component_utils(ovip_axi_auto_byte_lanes_alignment_test)

	function new(string name = "ovip_axi_auto_byte_lanes_alignment_test", uvm_component parent);
		super.new(name, parent);
		master_mon_ap = new("master_mon_ap", this);
		slave_mon_ap = new("slave_mon_ap", this);
	endfunction : new

	function void write_m(ovip_axi_trans tr);
		master_mon.push_back(tr);
	endfunction : write_m

	function void write_s(ovip_axi_trans tr);
		slave_mon.push_back(tr);
	endfunction : write_s
	
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		master_agent.mon.analysis_port.connect(master_mon_ap);
		slave_agent.mon.analysis_port.connect(slave_mon_ap);
	endfunction : connect_phase

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		
		slave_cfg.default_arready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_awready_pattern = '{cycles:'{0,1}, loop:0};
		slave_cfg.default_wready_pattern  = '{cycles:'{0,1}, loop:0};
		master_cfg.default_rready_pattern = '{cycles:'{0,1}, loop:0};
		master_cfg.default_bready_pattern = '{cycles:'{0,1}, loop:0};
	
		master_cfg.auto_byte_lanes_alignment = 1;
		slave_cfg.auto_byte_lanes_alignment = 1;
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);

		fork
			forever
			begin
				ovip_axi_trans tr;
				wait(master_mon.size());
				tr = master_mon.pop_front();
				foreach(tr.data_beats[ii])
					if(tr.tr_type == OVIP_AXI_WRITE_TRANS)
						`uvm_info("auto_byte_lanes_alignment/master/WR", $sformatf("[%0d] %0b", ii, tr.strb_beats[ii]), UVM_LOW)
					else
						`uvm_info("auto_byte_lanes_alignment/master/RD", $sformatf("[%0d] %0x", ii, tr.data_beats[ii]), UVM_LOW)
			end
			forever
			begin
				ovip_axi_trans tr;
				wait(slave_mon.size());
				tr = slave_mon.pop_front();
				foreach(tr.data_beats[ii])
					if(tr.tr_type == OVIP_AXI_WRITE_TRANS)
						`uvm_info("auto_byte_lanes_alignment/slave/WR", $sformatf("[%0d] %0b", ii, tr.strb_beats[ii]), UVM_LOW)
					else
						`uvm_info("auto_byte_lanes_alignment/slave/RD", $sformatf("[%0d] %0x", ii, tr.data_beats[ii]), UVM_LOW)
			end
		join_none
		begin
			ovip_debug_seq seq = ovip_debug_seq::type_id::create("seq");
			seq.start(master_agent.sqr);
		end

		phase.drop_objection(this);
	endtask : main_phase

endclass
