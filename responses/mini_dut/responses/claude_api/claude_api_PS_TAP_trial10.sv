```systemverilog
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
        SELECT_DR_SCAN   = 4'h2,
        CAPTURE_DR       = 4'h3,
        SHIFT_DR         = 4'h4,
        EXIT1_DR         = 4'h5,
        PAUSE_DR         = 4'h6,
        EXIT2_DR         = 4'h7,
        UPDATE_DR        = 4'h8,
        SELECT_IR_SCAN   = 4'h9,
        CAPTURE_IR       = 4'hA,
        SHIFT_IR         = 4'hB,
        EXIT1_IR         = 4'hC,
        PAUSE_IR         = 4'hD,
        EXIT2_IR         = 4'hE,
        UPDATE_IR        = 4'hF
    } tap_state_t;

    tap_state_t cur_state, nxt_state;

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            cur_state <= TEST_LOGIC_RESET;
        else
            cur_state <= nxt_state;
    end

    always_comb begin
        unique case (cur_state)
            TEST_LOGIC_RESET: nxt_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    nxt_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   nxt_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       nxt_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         nxt_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         nxt_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         nxt_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         nxt_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        nxt_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   nxt_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       nxt_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         nxt_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         nxt_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         nxt_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         nxt_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        nxt_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          nxt_state = TEST_LOGIC_RESET;
        endcase
    end

    assign state      = cur_state;
    assign shift_dr   = (cur_state == SHIFT_DR);
    assign capture_dr = (cur_state == CAPTURE_DR);
    assign update_dr  = (cur_state == UPDATE_DR);
    assign shift_ir   = (cur_state == SHIFT_IR);
    assign capture_ir = (cur_state == CAPTURE_IR);
    assign update_ir  = (cur_state == UPDATE_IR);

endmodule
```