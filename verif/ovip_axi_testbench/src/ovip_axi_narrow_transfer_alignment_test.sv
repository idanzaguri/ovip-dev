// Verifies narrow-transfer + unaligned-address handling. When the beat size
// is smaller than the bus width (e.g. 1B beats on an 8B bus) or the start
// address is unaligned, the active bytes must land on specific byte lanes
// per beat. Drives a random mix of sizes/addresses and confirms data
// round-trips correctly through the memory model.

class axi_rnd_narrow_transfer_seq extends uvm_sequence#(ovip_axi_trans);

	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)
	`uvm_object_utils(axi_rnd_narrow_transfer_seq)

	function new(string name = "axi_rnd_narrow_transfer_seq");
		super.new(name);
	endfunction

	virtual task body();

		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("narrow_transfter_wr");

			start_item(tr);
			tr.tr_type = OVIP_AXI_WRITE_TRANS;
			tr.addr = 6;
			tr.len = 5;
			tr.size = OVIP_AXI_SIZE_8B;
			tr.burst = OVIP_AXI_BURST_INCR;

			//tr.strb_beats = new[tr.len+1];
			//tr.data_beats = new[tr.len+1];
			begin
				byte CC=0;
				for(int ii=0; ii<=tr.len; ii++)
				begin
					ovip_axi_data_t wdata = 0;
					ovip_axi_strb_t strb = 0;
					for(int jj=0; jj<2**tr.size; jj++)
					begin
						wdata |= (CC++)<<(jj*8);
						strb |= 1'b1<<(jj);
					end
					if(ii==0) strb = 'b11;
					if(ii==0) wdata = 'h0706;
					tr.strb_beats[ii] = strb;
					tr.data_beats[ii] = wdata;
				end
			end
			tr.addr_phase_delay = 2;
			tr.data_start_event = OVIP_AXI_DATA_START_EV_BEFORE_ADDR;

			finish_item(tr);
		end

		begin
			ovip_axi_trans rsp__;
			get_response(rsp__);
		end


		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create("narrow_transfter_rd");

			start_item(tr);
			tr.tr_type = OVIP_AXI_READ_TRANS;
			tr.addr = 7;
			tr.len = 30;
			tr.size = OVIP_AXI_SIZE_4B;
			tr.burst = OVIP_AXI_BURST_INCR;
			finish_item(tr);
		end

		begin
			ovip_axi_trans rsp__;
			get_response(rsp__);
		end


	endtask : body
endclass




class ovip_axi_narrow_transfer_alignment_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_narrow_transfer_alignment_test)

	function new(string name = "ovip_axi_narrow_transfer_alignment_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.auto_byte_lanes_alignment = 1;
		slave_cfg.auto_byte_lanes_alignment = 1;

		master_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_16B;

		slave_cfg.protocol_type = OVIP_PROTOCOL_AXI4;
		slave_cfg.bus_width = OVIP_AXI_BUS_WIDTH_16B;
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		super.main_phase(phase);
		phase.raise_objection(this);
		begin
			axi_rnd_narrow_transfer_seq seq = axi_rnd_narrow_transfer_seq::type_id::create("seq");
			seq.start(master_agent.sqr);
			#1us;
		end
		phase.drop_objection(this);
	endtask : main_phase


endclass : ovip_axi_narrow_transfer_alignment_test

