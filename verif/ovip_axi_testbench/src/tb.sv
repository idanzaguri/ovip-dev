`timescale 1ns/1ps

module tb;
	import uvm_pkg::*;
	import ovip_global_pkg::*;
	import ovip_mem_pkg::*;
	import ovip_axi_pkg::*;
	import ovip_tests_pkg::*;
	logic clk,rst_n;

	// write address channel
	logic [`OVIP_AXI_MAX_ID_WIDTH-1:0] awid;
	logic [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] awaddr;
	logic [7:0] awlen;
	logic [3:0] awsize;
	logic [1:0] awburst;
	logic awvalid;
	logic awready;
	logic awlock;
	logic [3:0] awcache;
	logic [2:0] awprot;
	logic [3:0] awqos;
	logic [3:0] awregion;
	logic [`OVIP_AXI_MAX_USER_WIDTH-1:0] awuser;

	// write data channel
	logic [`OVIP_AXI_MAX_ID_WIDTH-1:0] wid;// only in AXI3
	logic [`OVIP_AXI_MAX_DATA_WIDTH-1:0] wdata;
	logic [`OVIP_AXI_MAX_STRB_WIDTH-1:0] wstrb;
	logic wlast;
	logic wvalid;
	logic wready;
	logic [`OVIP_AXI_MAX_USER_WIDTH-1:0] wuser;

	//write response channel
	logic [`OVIP_AXI_MAX_ID_WIDTH-1:0] bid;
	logic [1:0] bresp;
	logic bvalid;
	logic bready;
	logic [`OVIP_AXI_MAX_USER_WIDTH-1:0] buser;

	// read address channel
	logic [`OVIP_AXI_MAX_ID_WIDTH-1:0] arid;
	logic [`OVIP_AXI_MAX_ADDR_WIDTH-1:0] araddr;
	logic [7:0] arlen;
	logic [3:0] arsize;
	logic [1:0] arburst;
	logic arvalid;
	logic arready;
	logic arlock;
	logic [3:0] arcache;
	logic [2:0] arprot;
	logic [3:0] arqos;
	logic [3:0] arregion;
	logic [`OVIP_AXI_MAX_USER_WIDTH-1:0] ruser;

	//read data channel
	logic [`OVIP_AXI_MAX_ID_WIDTH-1:0] rid;
	logic [`OVIP_AXI_MAX_DATA_WIDTH-1:0] rdata;
	logic [1:0] rresp;
	logic rlast;
	logic rvalid;
	logic rready;
	logic [`OVIP_AXI_MAX_USER_WIDTH-1:0] aruser;

	ovip_axi_agent_if master_axi_if(clk,rst_n);
	ovip_axi_agent_if slave_axi_if(clk,rst_n);


	initial uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.master_agent*", "vif", master_axi_if);
	initial uvm_config_db#(virtual ovip_axi_agent_if)::set(null, "*.slave_agent*", "vif", slave_axi_if);

	// write address channel
	assign awid    = master_axi_if.awid;
	assign awaddr  = master_axi_if.awaddr;
	assign awlen   = master_axi_if.awlen;
	assign awsize  = master_axi_if.awsize;
	assign awburst = master_axi_if.awburst;
	assign awvalid = master_axi_if.awvalid;
	assign awlock  = master_axi_if.awlock;
	assign awcache = master_axi_if.awcache;
	assign awprot  = master_axi_if.awprot;
	assign awqos   = master_axi_if.awqos;
	assign awregion= master_axi_if.awregion;
	assign awuser  = master_axi_if.awuser;

	assign master_axi_if.awready = awready;

	// write data channel
	assign wid    = master_axi_if.wid;
	assign wdata  = master_axi_if.wdata;
	assign wstrb  = master_axi_if.wstrb;
	assign wlast  = master_axi_if.wlast;
	assign wuser  = master_axi_if.wuser;
	assign wvalid = master_axi_if.wvalid;
	assign master_axi_if.wready = wready;

	//write response channel
	assign master_axi_if.bid    = bid;
	assign master_axi_if.bresp  = bresp;
	assign master_axi_if.buser  = buser;
	assign master_axi_if.bvalid = bvalid;
	assign bready = master_axi_if.bready;

	// read address channel
	assign arid    = master_axi_if.arid;
	assign araddr  = master_axi_if.araddr;
	assign arlen   = master_axi_if.arlen;
	assign arsize  = master_axi_if.arsize;
	assign arburst = master_axi_if.arburst;
	assign arvalid = master_axi_if.arvalid;
	assign arlock  = master_axi_if.arlock;
	assign arcache = master_axi_if.arcache;
	assign arprot  = master_axi_if.arprot;
	assign arqos   = master_axi_if.arqos;
	assign arregion= master_axi_if.arregion;
	assign aruser  = master_axi_if.aruser;
	assign master_axi_if.arready = arready;

	//read data channel
	assign master_axi_if.rid     = rid;
	assign master_axi_if.rdata   = rdata;
	assign master_axi_if.rresp   = rresp;
	assign master_axi_if.rlast   = rlast;
	assign master_axi_if.ruser   = ruser;
	assign master_axi_if.rvalid  = rvalid;
	assign rready = master_axi_if.rready;


	// write address channel
	assign slave_axi_if.awid    = awid;
	assign slave_axi_if.awaddr  = awaddr;
	assign slave_axi_if.awlen   = awlen;
	assign slave_axi_if.awsize  = awsize;
	assign slave_axi_if.awburst = awburst;
	assign slave_axi_if.awvalid = awvalid;
	assign slave_axi_if.awlock  = awlock;
	assign slave_axi_if.awcache = awcache;
	assign slave_axi_if.awprot  = awprot;
	assign slave_axi_if.awqos   = awqos;
	assign slave_axi_if.awregion= awregion;
	assign slave_axi_if.awuser  = awuser;
	assign awready = slave_axi_if.awready;

	// write data channel
	assign slave_axi_if.wid    = wid;
	assign slave_axi_if.wdata  = wdata;
	assign slave_axi_if.wstrb  = wstrb;
	assign slave_axi_if.wlast  = wlast;
	assign slave_axi_if.wuser  = wuser;
	assign slave_axi_if.wvalid = wvalid;
	assign wready =slave_axi_if.wready;

	//write response channel
	assign bid    = slave_axi_if.bid;
	assign bresp  = slave_axi_if.bresp;
	assign buser  = slave_axi_if.buser;
	assign bvalid = slave_axi_if.bvalid;
	assign slave_axi_if.bready  = bready;

	// read address channel
	assign slave_axi_if.arid    = arid;
	assign slave_axi_if.araddr  = araddr;
	assign slave_axi_if.arlen   = arlen;
	assign slave_axi_if.arsize  = arsize;
	assign slave_axi_if.arburst = arburst;
	assign slave_axi_if.arvalid = arvalid;
	assign slave_axi_if.arlock  = arlock;
	assign slave_axi_if.arcache = arcache;
	assign slave_axi_if.arprot  = arprot;
	assign slave_axi_if.arqos   = arqos;
	assign slave_axi_if.arregion= arregion;
	assign slave_axi_if.aruser  = aruser;
	assign arready = slave_axi_if.arready;

	//read data channel
	assign rid     = slave_axi_if.rid;
	assign rdata   = slave_axi_if.rdata;
	assign rresp   = slave_axi_if.rresp;
	assign rlast   = slave_axi_if.rlast;
	assign ruser   = slave_axi_if.ruser;
	assign rvalid  = slave_axi_if.rvalid;
	assign slave_axi_if.rready = rready;


	`ifdef TEST_NAME // used when running simulation via EDA-Playground
		initial begin
			$dumpfile("dump.vcd"); $dumpvars;
			run_test(`TEST_NAME);
		end

	`else
		initial run_test();
	`endif
	initial
	begin
		$timeformat(-9,1,"ns");
		clk=1;
		rst_n=1;
		fork forever #500ps clk = ~clk; join_none;
		repeat(2) @(posedge clk);
		rst_n=0;
		repeat(2) @(posedge clk);
		rst_n=1;
	end

	int rd_counter_nxt,rd_counter;
	int wr_counter_nxt,wr_counter;
	int counter;
	assign counter = rd_counter+wr_counter;

	always @(posedge clk)
	begin
		if(~rst_n) rd_counter <= 0;
		else rd_counter <= rd_counter_nxt;
	end

	always @(posedge clk)
	begin
		if(~rst_n) wr_counter <= 0;
		else wr_counter <= wr_counter_nxt;
	end
	always_comb
	begin
		rd_counter_nxt = rd_counter;
		wr_counter_nxt = wr_counter;
		if(awvalid & awready) wr_counter_nxt += 1;
		if(arvalid & arready) rd_counter_nxt += 1;
		if(rvalid & rready & rlast) rd_counter_nxt -= 1;
		if(bvalid & bready) wr_counter_nxt -= 1;
	end



endmodule : tb
