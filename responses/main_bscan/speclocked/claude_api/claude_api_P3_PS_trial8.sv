```systemverilog
module tap_controller (
    input  logic        tck,
    input  logic        tms,
    input  logic        tdi,
    input  logic        trst_n,
    output logic        tdo,
    output logic        tdo_en,
    output logic        shift_dr,
    output logic        capture_dr,
    output logic        update_dr,
    output logic        shift_ir,
    output logic        capture_ir,
    output logic        update_ir,
    input  logic        bsr_tdo,
    input  logic        tdr_tdo,
    output logic        tdr_select,
    output logic [3:0]  ir_reg_out
);

    // TAP states
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

    tap_state_t state, next_state;

    // Instruction opcodes
    localparam logic [3:0] INST_EXTEST = 4'b0010;
    localparam logic [3:0] INST_SAMPLE = 4'b0011;
    localparam logic [3:0] INST_CLAMP  = 4'b0110;
    localparam logic [3:0] INST_UTDR   = 4'b0111;
    localparam logic [3:0] INST_IDCODE = 4'b1110;
    localparam logic [3:0] INST_BYPASS = 4'b1111;

    // Registers
    logic [3:0]  ir_shift;
    logic [3:0]  ir_hold;
    logic [31:0] idcode_shift;
    logic        bypass_reg;

    // -------------------------------------------------------------
    // State register (posedge TCK, async reset to TLR)
    // -------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            state <= TEST_LOGIC_RESET;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------------
    always_comb begin
        unique case (state)
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

    // -------------------------------------------------------------
    // State decoded outputs
    // -------------------------------------------------------------
    assign capture_dr = (state == CAPTURE_DR);
    assign shift_dr   = (state == SHIFT_DR);
    assign update_dr  = (state == UPDATE_DR);
    assign capture_ir = (state == CAPTURE_IR);
    assign shift_ir   = (state == SHIFT_IR);
    assign update_ir  = (state == UPDATE_IR);

    assign tdo_en = shift_dr || shift_ir;

    // -------------------------------------------------------------
    // Instruction Register
    // -------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift <= 4'b0000;
            ir_hold  <= INST_IDCODE;
        end else begin
            case (state)
                TEST_LOGIC_RESET: begin
                    ir_hold  <= INST_IDCODE;
                end
                CAPTURE_IR: begin
                    // Fixed pattern: lower 2 bits = 01 per 1149.1
                    ir_shift <= 4'b0001;
                end
                SHIFT_IR: begin
                    ir_shift <= {tdi, ir_shift[3:1]};
                end
                UPDATE_IR: begin
                    ir_hold <= ir_shift;
                end
                default: ;
            endcase
        end
    end

    assign ir_reg_out = ir_hold;
    assign tdr_select = (ir_hold == INST_UTDR);

    // -------------------------------------------------------------
    // IDCODE shift register
    // -------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift <= 32'hDEADBEEF;
        end else begin
            if (state == CAPTURE_DR && ir_hold == INST_IDCODE) begin
                idcode_shift <= 32'hDEADBEEF;
            end else if (state == SHIFT_DR && ir_hold == INST_IDCODE) begin
                idcode_shift <= {tdi, idcode_shift[31:1]};
            end
        end
    end

    // -------------------------------------------------------------
    // BYPASS register (also used by CLAMP and as default DR)
    // -------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end else begin
            if (state == CAPTURE_DR) begin
                bypass_reg <= 1'b0;
            end else if (state == SHIFT_DR) begin
                bypass_reg <= tdi;
            end
        end
    end

    // -------------------------------------------------------------
    // TDO output - launched on negedge TCK
    // -------------------------------------------------------------
    logic tdo_next;

    always_comb begin
        tdo_next = 1'b0;
        if (state == SHIFT_IR) begin
            tdo_next = ir_shift[0];
        end else if (state == SHIFT_DR) begin
            unique case (ir_hold)
                INST_EXTEST,
                INST_SAMPLE: tdo_next = bsr_tdo;
                INST_IDCODE: tdo_next = idcode_shift[0];
                INST_UTDR:   tdo_next = tdr_tdo;
                default:     tdo_next = bypass_reg; // BYPASS, CLAMP, others
            endcase
        end
    end

    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n)
            tdo <= 1'b0;
        else
            tdo <= tdo_next;
    end

endmodule
```