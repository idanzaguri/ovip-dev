`ifndef OVIP_ACE_PKG__SV
`define OVIP_ACE_PKG__SV

`include "ovip_axi_defines.sv"
`include "ovip_ace_defines.sv"
`include "ovip_ace_agent_if.sv"

package ovip_ace_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	import ovip_global_pkg::*;
	import ovip_axi_pkg::*;

	`include "ovip_ace_types.sv"
	`include "ovip_ace_agent_config.sv"
	`include "ovip_ace_trans.sv"

	// Driver, monitor, agent, scoreboard, sequence library land in the next
	// commits. The foundation here -- types/config/trans/interface -- compiles
	// standalone so the wiring up of the rest can be incremental.
endpackage : ovip_ace_pkg

`endif
