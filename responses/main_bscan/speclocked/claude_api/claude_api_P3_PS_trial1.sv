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

    // Instructions
    localparam logic [3:0] INST_EXTEST = 4'b0010;
    localparam logic [3:0] INST_SAMPLE = 4'b0011;
    localparam logic [3:0] INST_CLAMP  = 4'b0110;
    localparam logic [3:0] INST_UTDR   = 4'b0111;
    localparam logic [3:0] INST_IDCODE = 4'b1110;
    localparam logic [3:0] INST_BYPASS = 4'b1111;

    tap_state_t current_state, next_state;

    // IR shift and hold registers
    logic [3:0] ir_shift_reg;
    logic [3:0] ir_hold_reg;

    // IDCODE shift register
    logic [31:0] idcode_shift_reg;

    // BYPASS register
    logic bypass_reg;

    // State register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            current_state <= TEST_LOGIC_RESET;
        else
            current_state <= next_state;
    end

    // Next state logic
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

    // State decode outputs
    assign capture_dr = (current_state == CAPTURE_DR);
    assign shift_dr   = (current_state == SHIFT_DR);
    assign update_dr  = (current_state == UPDATE_DR);
    assign capture_ir = (current_state == CAPTURE_IR);
    assign shift_ir   = (current_state == SHIFT_IR);
    assign update_ir  = (current_state == UPDATE_IR);

    // IR shift register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift_reg <= 4'b0000;
        end else begin
            case (current_state)
                CAPTURE_IR: ir_shift_reg <= 4'b0001; // standard capture value
                SHIFT_IR:   ir_shift_reg <= {tdi, ir_shift_reg[3:1]};
                default:    ir_shift_reg <= ir_shift_reg;
            endcase
        end
    end

    // IR hold register (updates on UPDATE_IR), resets to IDCODE on TRST_N
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_hold_reg <= INST_IDCODE;
        end else if (current_state == TEST_LOGIC_RESET) begin
            ir_hold_reg <= INST_IDCODE;
        end else if (current_state == UPDATE_IR) begin
            ir_hold_reg <= ir_shift_reg;
        end
    end

    assign ir_reg_out = ir_hold_reg;
    assign tdr_select = (ir_hold_reg == INST_UTDR);

    // IDCODE shift register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift_reg <= 32'hDEADBEEF;
        end else begin
            if (current_state == CAPTURE_DR && ir_hold_reg == INST_IDCODE) begin
                idcode_shift_reg <= 32'hDEADBEEF;
            end else if (current_state == SHIFT_DR && ir_hold_reg == INST_IDCODE) begin
                idcode_shift_reg <= {tdi, idcode_shift_reg[31:1]};
            end
        end
    end

    // BYPASS register (1-bit) used for BYPASS and CLAMP and default
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end else begin
            if (current_state == CAPTURE_DR) begin
                bypass_reg <= 1'b0;
            end else if (current_state == SHIFT_DR) begin
                // capture tdi into bypass when bypass-like selected
                if ((ir_hold_reg != INST_IDCODE) &&
                    (ir_hold_reg != INST_UTDR) &&
                    (ir_hold_reg != INST_EXTEST) &&
                    (ir_hold_reg != INST_SAMPLE)) begin
                    bypass_reg <= tdi;
                end
            end
        end
    end

    // TDO launched on negedge TCK
    logic tdo_r;
    logic tdo_en_r;

    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tdo_r    <= 1'b0;
            tdo_en_r <= 1'b0;
        end else begin
            if (current_state == SHIFT_IR) begin
                tdo_r    <= ir_shift_reg[0];
                tdo_en_r <= 1'b1;
            end else if (current_state == SHIFT_DR) begin
                tdo_en_r <= 1'b1;
                case (ir_hold_reg)
                    INST_EXTEST, INST_SAMPLE: tdo_r <= bsr_tdo;
                    INST_IDCODE:              tdo_r <= idcode_shift_reg[0];
                    INST_UTDR:                tdo_r <= tdr_tdo;
                    default:                  tdo_r <= bypass_reg;
                endcase
            end else begin
                tdo_en_r <= 1'b0;
                tdo_r    <= 1'b0;
            end
        end
    end

    assign tdo    = tdo_r;
    assign tdo_en = tdo_en_r;

endmodule
```