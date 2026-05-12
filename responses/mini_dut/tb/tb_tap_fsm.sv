//-----------------------------------------------------------------------------
// tb_tap_fsm -- Reference testbench for the mini-DUT TAP FSM.
// Observes only the mandated PORT CONTRACT (tck/tms/trst_n inputs, state[3:0]
// + six one-hot state-decode strobes as outputs). State encoding values are
// NOT checked numerically (the spec does not mandate encoding), only the
// six one-hot strobes and that exactly one strobe is high at a time in
// SHIFT/CAPTURE/UPDATE states are checked. Reachability is tested by
// replaying canonical TMS sequences from Reset.
//
// PASS/FAIL tags are printed so the scoring harness can grep them.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_tap_fsm;

    logic tck    = 0;
    logic tms    = 1;
    logic trst_n = 0;

    logic [3:0] state;
    logic shift_dr, capture_dr, update_dr;
    logic shift_ir, capture_ir, update_ir;

    int pass_cnt = 0;
    int fail_cnt = 0;

    tap_fsm dut (
        .tck(tck),
        .tms(tms),
        .trst_n(trst_n),
        .state(state),
        .shift_dr(shift_dr),
        .capture_dr(capture_dr),
        .update_dr(update_dr),
        .shift_ir(shift_ir),
        .capture_ir(capture_ir),
        .update_ir(update_ir)
    );

    // 50 MHz TCK
    always #10 tck = ~tck;

    // Apply one TCK cycle with specified TMS. Sample outputs just after
    // the rising edge.
    task automatic tck_cycle(input bit tms_val);
        @(negedge tck);
        tms = tms_val;
        @(posedge tck);
        #1;
    endtask

    task automatic check(input string name, input bit cond);
        if (cond) begin
            $display("PASS: %s", name);
            pass_cnt++;
        end else begin
            $display("FAIL: %s  (strobes=%b%b%b%b%b%b state=%0h)",
                     name, shift_dr, capture_dr, update_dr,
                     shift_ir, capture_ir, update_ir, state);
            fail_cnt++;
        end
    endtask

    // Helper: count of strobes high
    function automatic int strobe_sum;
        strobe_sum = shift_dr + capture_dr + update_dr
                   + shift_ir + capture_ir + update_ir;
    endfunction

    // Helper: reset into TEST_LOGIC_RESET via 5 TMS=1 cycles
    task automatic goto_reset;
        trst_n = 0;
        tms    = 1;
        repeat (3) @(posedge tck);
        #1;
        trst_n = 1;
        // 5 cycles of tms=1 guarantees TEST_LOGIC_RESET per IEEE 1149.1
        repeat (5) tck_cycle(1);
    endtask

    initial begin
        $display("=== tb_tap_fsm start ===");
        goto_reset();
        check("reset_no_strobes", strobe_sum() == 0);

        // TMS=0 -> RUN_TEST_IDLE (no strobes)
        tck_cycle(0);
        check("rti_no_strobes", strobe_sum() == 0);

        // Navigate: RTI -> SELECT_DR -> CAPTURE_DR
        tck_cycle(1);  // -> SELECT_DR
        check("select_dr_no_strobes", strobe_sum() == 0);
        tck_cycle(0);  // -> CAPTURE_DR
        check("capture_dr_strobe", capture_dr && (strobe_sum() == 1));

        // CAPTURE_DR -> SHIFT_DR
        tck_cycle(0);
        check("shift_dr_strobe", shift_dr && (strobe_sum() == 1));

        // Stay in SHIFT_DR for 3 more cycles
        tck_cycle(0);
        tck_cycle(0);
        tck_cycle(0);
        check("shift_dr_sticky", shift_dr && (strobe_sum() == 1));

        // SHIFT_DR -> EXIT1_DR -> UPDATE_DR
        tck_cycle(1);  // EXIT1_DR
        check("exit1_dr_no_strobes", strobe_sum() == 0);
        tck_cycle(1);  // UPDATE_DR
        check("update_dr_strobe", update_dr && (strobe_sum() == 1));

        // UPDATE_DR -> RTI (tms=0)
        tck_cycle(0);
        check("post_update_rti", strobe_sum() == 0);

        // IR path: RTI -> SELECT_DR -> SELECT_IR -> CAPTURE_IR -> SHIFT_IR
        tck_cycle(1);  // SELECT_DR
        tck_cycle(1);  // SELECT_IR
        tck_cycle(0);  // CAPTURE_IR
        check("capture_ir_strobe", capture_ir && (strobe_sum() == 1));
        tck_cycle(0);  // SHIFT_IR
        check("shift_ir_strobe", shift_ir && (strobe_sum() == 1));

        // SHIFT_IR -> EXIT1_IR -> UPDATE_IR
        tck_cycle(1);  // EXIT1_IR
        check("exit1_ir_no_strobes", strobe_sum() == 0);
        tck_cycle(1);  // UPDATE_IR
        check("update_ir_strobe", update_ir && (strobe_sum() == 1));

        // Async TRST_N returns to TEST_LOGIC_RESET with no strobes
        trst_n = 0;
        #5;
        check("async_trst_clears", strobe_sum() == 0);
        trst_n = 1;
        repeat (5) tck_cycle(1);
        check("rereset_no_strobes", strobe_sum() == 0);

        $display("=== tb_tap_fsm done: %0d pass, %0d fail ===",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0 && pass_cnt >= 13) $display("RESULT: ALL_PASS");
        else                                 $display("RESULT: HAS_FAIL");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $display("RESULT: HAS_FAIL");
        $finish;
    end

endmodule
