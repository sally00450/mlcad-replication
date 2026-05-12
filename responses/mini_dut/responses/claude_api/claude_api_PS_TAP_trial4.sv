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
    } tap_state_e;

    tap_state_e cs, ns;

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            cs <= TEST_LOGIC_RESET;
        else
            cs <= ns;
    end

    always_comb begin
        unique case (cs)
            TEST_LOGIC_RESET: ns = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    ns = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   ns = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       ns = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         ns = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         ns = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         ns = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         ns = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        ns = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   ns = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       ns = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         ns = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         ns = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         ns = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         ns = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        ns = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          ns = TEST_LOGIC_RESET;
        endcase
    end

    assign state      = cs;
    assign capture_dr = (cs == CAPTURE_DR);
    assign shift_dr   = (cs == SHIFT_DR);
    assign update_dr  = (cs == UPDATE_DR);
    assign capture_ir = (cs == CAPTURE_IR);
    assign shift_ir   = (cs == SHIFT_IR);
    assign update_ir  = (cs == UPDATE_IR);

endmodule
```