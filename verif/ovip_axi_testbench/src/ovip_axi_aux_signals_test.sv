`ifndef OVIP_AXI_AUX_SIGNALS_TEST__SV
`define OVIP_AXI_AUX_SIGNALS_TEST__SV

// Exercises the optional AXI signals end-to-end so they're regression-covered:
//   - axlock / axcache / axprot / axqos / axregion (each gated by its cfg.*_en bit)
//   - the five *user fields (each gated by its cfg.*user_width)
//
// The base test's slave loopback handles data integrity; this test additionally
// drives non-zero values on every aux signal in both directions (master->slave
// for axlock/cache/prot/qos/region + awuser/wuser/aruser; slave->master for
// buser/ruser, via a small base-slave-seq subclass) and lets the monitor catch
// any masking / width-gating bugs.


// Master-side sequence that drives non-zero values on the aux fields and varies
// them across iterations so different bit patterns get exercised. Extends
// ovip_axi_base_master_sequence so send() / wait_for_responses() take care of
// the get/put bookkeeping.
class aux_signals_master_seq extends ovip_axi_base_master_sequence;
	`uvm_object_utils(aux_signals_master_seq)
	`uvm_declare_p_sequencer(ovip_axi_base_sequencer)

	function new(string name = "aux_signals_master_seq");
		super.new(name);
	endfunction

	virtual task body();
		// Eight WRITE transactions.
		for(int ii = 0; ii < 8; ii++)
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("wr_%0d", ii));
			tr.tr_type = OVIP_AXI_WRITE_TRANS;
			tr.addr    = ii * 32;
			tr.id      = ii & 3;
			tr.len     = 1;
			tr.size    = OVIP_AXI_SIZE_4B;
			tr.burst   = OVIP_AXI_BURST_INCR;
			tr.data_beats = '{32'hAABB_CC00 + ii, 32'h1122_3300 + ii};
			// auto-byte-lane alignment is on (base default), so STRB is lane-0-aligned
			// and the driver shifts it into the correct byte lane per beat.
			// 4B beat -> 4 active lanes -> 8'h0F.
			tr.strb_beats = '{8'h0F, 8'h0F};

			tr.awuser   = 4'(ii ^ 4'h5);
			tr.wuser    = 4'(ii ^ 4'h6);
			tr.axlock   = ii[0];
			tr.axcache  = 4'(ii);
			tr.axprot   = 3'(ii);
			tr.axqos    = 4'(ii ^ 4'h9);
			tr.axregion = 4'(ii ^ 4'hC);
			send(tr);
		end

		// Eight READ transactions.
		for(int ii = 0; ii < 8; ii++)
		begin
			ovip_axi_trans tr = ovip_axi_trans::type_id::create($sformatf("rd_%0d", ii));
			tr.tr_type = OVIP_AXI_READ_TRANS;
			tr.addr    = ii * 32;
			tr.id      = ii & 3;
			tr.len     = 1;
			tr.size    = OVIP_AXI_SIZE_4B;
			tr.burst   = OVIP_AXI_BURST_INCR;

			tr.aruser   = 4'(ii ^ 4'h7);
			tr.axlock   = ii[0];
			tr.axcache  = 4'(ii);
			tr.axprot   = 3'(ii);
			tr.axqos    = 4'(ii ^ 4'h9);
			tr.axregion = 4'(ii ^ 4'hC);
			send(tr);
		end

		// Block until every in-flight transaction's response has come back.
		wait_for_responses();
	endtask : body
endclass : aux_signals_master_seq


// Slave sequence subclass that injects non-zero buser/ruser values so the
// slave-to-master half of the *user round-trip is also exercised. The body()
// mirrors ovip_axi_base_slave_sequence::body() with one extra assignment on
// each path; see the base class for the structural reasoning (reset-race
// watcher, etc.).
class aux_signals_slave_seq extends ovip_axi_base_slave_sequence;
	`uvm_object_utils(aux_signals_slave_seq)

	function new(string name = "aux_signals_slave_seq");
		super.new(name);
	endfunction

	virtual task body();
		forever
		begin
			p_sequencer.response_req_port.get(req);
			start_item(req);

			if(req.monitor_error)
			begin
				req.resp = OVIP_AXI_RESP_SLVERR;
				if(req.tr_type == OVIP_AXI_READ_TRANS)
					repeat(req.len+1) req.data_beats.push_back(0);
				else
					req.bresp_delay = 0;
				finish_item(req);
				continue;
			end

			req.resp = OVIP_AXI_RESP_OKAY;

			if(req.tr_type == OVIP_AXI_READ_TRANS)
			begin
				populate_data_from_mem(req);
				set_read_trans_delays(req);
				req.ruser = req.id ^ 4'hA;
			end
			else
			begin
				req.bresp_delay = get_bresp_delay();
				req.buser       = req.id ^ 4'h5;
				fork
					begin
						ovip_axi_trans _req = req;
						fork
							wait(_req.transaction_finished);
							@(p_sequencer.vif.monitor_cb iff !p_sequencer.vif.monitor_cb.aresetn);
						join_any
						disable fork;
						if(_req.transaction_finished)
							write_transaction_to_mem(_req);
					end
				join_none
			end

			finish_item(req);
		end
	endtask : body
endclass : aux_signals_slave_seq


class ovip_axi_aux_signals_test extends ovip_axi_base_test;

	`uvm_component_utils(ovip_axi_aux_signals_test)

	function new(string name = "ovip_axi_aux_signals_test", uvm_component parent);
		super.new(name, parent);
	endfunction : new

	function void enable_aux_signals(ovip_axi_agent_config cfg);
		cfg.awlock_en    = 1;
		cfg.awcache_en   = 1;
		cfg.awprot_en    = 1;
		cfg.awqos_en     = 1;
		cfg.awregion_en  = 1;
		cfg.arlock_en    = 1;
		cfg.arcache_en   = 1;
		cfg.arprot_en    = 1;
		cfg.arqos_en     = 1;
		cfg.arregion_en  = 1;
		cfg.awuser_width = 4;
		cfg.wuser_width  = 4;
		cfg.buser_width  = 4;
		cfg.aruser_width = 4;
		cfg.ruser_width  = 4;
	endfunction : enable_aux_signals

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		master_cfg.bus_width = OVIP_AXI_BUS_WIDTH_8B;
		slave_cfg.bus_width  = OVIP_AXI_BUS_WIDTH_8B;

		enable_aux_signals(master_cfg);
		enable_aux_signals(slave_cfg);

		// Replace the default slave sequence with our subclass so buser/ruser
		// carry non-zero values on the response path.
		slave_seq     = aux_signals_slave_seq::type_id::create("slave_seq");
		slave_seq.mem = mem;
	endfunction : build_phase

	task main_phase(uvm_phase phase);
		aux_signals_master_seq seq = aux_signals_master_seq::type_id::create("seq");
		super.main_phase(phase);
		phase.raise_objection(this);
		seq.start(master_agent.sqr);
		#100ns;
		phase.drop_objection(this);
	endtask : main_phase

endclass : ovip_axi_aux_signals_test

`endif
