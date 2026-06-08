`ifndef OVIP_AXI_STREAM_EXPECTED_ERRORS_REPORT_SERVER__SV
`define OVIP_AXI_STREAM_EXPECTED_ERRORS_REPORT_SERVER__SV

// Custom UVM report server used by ovip_axi_stream_base_test. Tests register
// the regex of an error they *expect* to fire (via expected_errors.push_back);
// when an UVM_ERROR matches a registered pattern, it is silently absorbed
// instead of bumping the global error count. Unmatched expected errors are
// flagged in final_phase as MISSING_EXP_ERROR.
//
// `in_order = 1` requires the errors to fire in the order they were pushed.
// Tests that don't care about order leave it at 0.

class ovip_axi_stream_expected_errors_report_server extends uvm_default_report_server;
	string message_queue[$];
	string expected_errors[$];
	bit    in_order;

	virtual function void execute_report_message(uvm_report_message report_message, string composed_message);
		if(report_message.get_severity() == UVM_ERROR && expected_errors.size())
		begin
			message_queue.push_back(composed_message);
			foreach(expected_errors[ii])
			begin
				if(uvm_re_match(expected_errors[ii], composed_message) == 0)
				begin
					expected_errors.delete(ii);
					return;
				end
				if(in_order) break;
			end
		end
		super.execute_report_message(report_message, composed_message);
	endfunction
endclass

`endif
