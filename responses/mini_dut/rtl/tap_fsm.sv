//-----------------------------------------------------------------------------
// Module:      tap_fsm  (mini-DUT reference)
// Description: IEEE 1149.1 TAP state machine ONLY. No IR, no DR chain,
//              no BSR/BYPASS/IDCODE. Inputs: TCK/TMS/TRST_N. Outputs:
//              4-bit encoded state and six one-hot state-decode strobes.
//              This is a deliberately minimal scope to probe whether the
//              PS (spec-locked) prompting remedy generalizes beyond the
//              full BSCAN demo.
//-----------------------------------------------------------------------------
module tap_fsm (
    input  logic       tck,
    input  logic       tms,
    input  logic       trst_n,
    output logic [3:0] state,
    output logic       shift_dr,
    output logic       capture_dr,
    output logic       update_dr,
    output logic       shift_ir,
    output logic       capture_ir,
    output logic       update_ir
);

    typedef enum logic [3:0] {
        TEST_LOGIC_RESET = 4'h0,
        RUN_TEST_IDLE    = 4'h1,
        SELECT_DR        = 4'h2,
        CAPTURE_DR       = 4'h3,
        SHIFT_DR         = 4'h4,
        EXIT1_DR         = 4'h5,
        PAUSE_DR         = 4'h6,
        EXIT2_DR         = 4'h7,
        UPDATE_DR        = 4'h8,
        SELECT_IR        = 4'h9,
        CAPTURE_IR       = 4'hA,
        SHIFT_IR         = 4'hB,
        EXIT1_IR         = 4'hC,
        PAUSE_IR         = 4'hD,
        EXIT2_IR         = 4'hE,
        UPDATE_IR        = 4'hF
    } tap_state_e;

    tap_state_e cur, nxt;

    always_comb begin
        case (cur)
            TEST_LOGIC_RESET: nxt = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    nxt = tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_DR:        nxt = tms ? SELECT_IR        : CAPTURE_DR;
            CAPTURE_DR:       nxt = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         nxt = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         nxt = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         nxt = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         nxt = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        nxt = tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_IR:        nxt = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       nxt = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         nxt = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         nxt = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         nxt = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         nxt = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        nxt = tms ? SELECT_DR        : RUN_TEST_IDLE;
            default:          nxt = TEST_LOGIC_RESET;
        endcase
    end

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) cur <= TEST_LOGIC_RESET;
        else         cur <= nxt;
    end

    assign state      = cur;
    assign shift_dr   = (cur == SHIFT_DR);
    assign capture_dr = (cur == CAPTURE_DR);
    assign update_dr  = (cur == UPDATE_DR);
    assign shift_ir   = (cur == SHIFT_IR);
    assign capture_ir = (cur == CAPTURE_IR);
    assign update_ir  = (cur == UPDATE_IR);

endmodule
