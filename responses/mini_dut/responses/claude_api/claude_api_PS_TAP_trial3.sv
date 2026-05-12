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

    localparam logic [3:0] TEST_LOGIC_RESET = 4'h0;
    localparam logic [3:0] RUN_TEST_IDLE    = 4'h1;
    localparam logic [3:0] SELECT_DR_SCAN   = 4'h2;
    localparam logic [3:0] CAPTURE_DR       = 4'h3;
    localparam logic [3:0] SHIFT_DR         = 4'h4;
    localparam logic [3:0] EXIT1_DR         = 4'h5;
    localparam logic [3:0] PAUSE_DR         = 4'h6;
    localparam logic [3:0] EXIT2_DR         = 4'h7;
    localparam logic [3:0] UPDATE_DR        = 4'h8;
    localparam logic [3:0] SELECT_IR_SCAN   = 4'h9;
    localparam logic [3:0] CAPTURE_IR       = 4'hA;
    localparam logic [3:0] SHIFT_IR         = 4'hB;
    localparam logic [3:0] EXIT1_IR         = 4'hC;
    localparam logic [3:0] PAUSE_IR         = 4'hD;
    localparam logic [3:0] EXIT2_IR         = 4'hE;
    localparam logic [3:0] UPDATE_IR        = 4'hF;

    logic [3:0] current_state, next_state;

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            current_state <= TEST_LOGIC_RESET;
        else
            current_state <= next_state;
    end

    always_comb begin
        unique case (current_state)
            TEST_LOGIC_RESET: next_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   next_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR:       next_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         next_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         next_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         next_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         next_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   next_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       next_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         next_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         next_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         next_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         next_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default:          next_state = TEST_LOGIC_RESET;
        endcase
    end

    assign state      = current_state;
    assign capture_dr = (current_state == CAPTURE_DR);
    assign shift_dr   = (current_state == SHIFT_DR);
    assign update_dr  = (current_state == UPDATE_DR);
    assign capture_ir = (current_state == CAPTURE_IR);
    assign shift_ir   = (current_state == SHIFT_IR);
    assign update_ir  = (current_state == UPDATE_IR);

endmodule
```