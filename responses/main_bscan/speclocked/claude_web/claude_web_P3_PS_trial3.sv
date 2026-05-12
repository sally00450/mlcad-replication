```systemverilog
//-----------------------------------------------------------------------------
// Module      : tap_controller
// Description : IEEE 1149.1 JTAG TAP Controller
//               - 16-state TAP FSM
//               - 4-bit Instruction Register with IDCODE default
//               - 32-bit IDCODE shift register (0xDEADBEEF)
//               - 1-bit BYPASS / CLAMP register
//               - Negedge-TCK launched TDO
//-----------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // TAP FSM state encoding (16 states - 4 bits)
    //-------------------------------------------------------------------------
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

    tap_state_e current_state, next_state;

    //-------------------------------------------------------------------------
    // Instruction opcodes (4-bit)
    //-------------------------------------------------------------------------
    localparam logic [3:0] INSTR_EXTEST = 4'b0010;
    localparam logic [3:0] INSTR_SAMPLE = 4'b0011;
    localparam logic [3:0] INSTR_CLAMP  = 4'b0110;
    localparam logic [3:0] INSTR_UTDR   = 4'b0111;
    localparam logic [3:0] INSTR_IDCODE = 4'b1110;
    localparam logic [3:0] INSTR_BYPASS = 4'b1111;

    //-------------------------------------------------------------------------
    // Internal registers
    //-------------------------------------------------------------------------
    logic [3:0]  ir_shift_reg;   // IR shift path
    logic [3:0]  ir_hold_reg;    // IR hold (current instruction)
    logic [31:0] idcode_shift;   // IDCODE shift register
    logic        bypass_reg;     // BYPASS / CLAMP single-bit register

    //-------------------------------------------------------------------------
    // FSM: state register (posedge TCK, async TRST_N)
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            current_state <= TEST_LOGIC_RESET;
        else
            current_state <= next_state;
    end

    //-------------------------------------------------------------------------
    // FSM: next-state logic (per IEEE 1149.1 state diagram)
    //-------------------------------------------------------------------------
    always_comb begin
        unique case (current_state)
            TEST_LOGIC_RESET: next_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE   : next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_DR_SCAN  : next_state = tms ? SELECT_IR_SCAN   : CAPTURE_DR;
            CAPTURE_DR      : next_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR        : next_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR        : next_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR        : next_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR        : next_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR       : next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            SELECT_IR_SCAN  : next_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR      : next_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR        : next_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR        : next_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR        : next_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR        : next_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR       : next_state = tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
            default         : next_state = TEST_LOGIC_RESET;
        endcase
    end

    //-------------------------------------------------------------------------
    // FSM control output decoding
    //-------------------------------------------------------------------------
    assign capture_dr = (current_state == CAPTURE_DR);
    assign shift_dr   = (current_state == SHIFT_DR);
    assign update_dr  = (current_state == UPDATE_DR);
    assign capture_ir = (current_state == CAPTURE_IR);
    assign shift_ir   = (current_state == SHIFT_IR);
    assign update_ir  = (current_state == UPDATE_IR);

    //-------------------------------------------------------------------------
    // Instruction Register
    //   - Shift path: capture loads 4'b0001 (status pattern, LSB=1 per spec),
    //                 shift moves bits with TDI into MSB
    //   - Hold path : updates on UPDATE_IR; resets to IDCODE on TLR
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift_reg <= 4'b0001;
        end
        else begin
            case (current_state)
                TEST_LOGIC_RESET: ir_shift_reg <= 4'b0001;
                CAPTURE_IR      : ir_shift_reg <= 4'b0001;
                SHIFT_IR        : ir_shift_reg <= {tdi, ir_shift_reg[3:1]};
                default         : ir_shift_reg <= ir_shift_reg;
            endcase
        end
    end

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_hold_reg <= INSTR_IDCODE;
        end
        else begin
            case (current_state)
                TEST_LOGIC_RESET: ir_hold_reg <= INSTR_IDCODE;
                UPDATE_IR       : ir_hold_reg <= ir_shift_reg;
                default         : ir_hold_reg <= ir_hold_reg;
            endcase
        end
    end

    assign ir_reg_out = ir_hold_reg;

    //-------------------------------------------------------------------------
    // IDCODE shift register (loaded with 0xDEADBEEF on capture)
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift <= 32'hDEAD_BEEF;
        end
        else if (capture_dr && (ir_hold_reg == INSTR_IDCODE)) begin
            idcode_shift <= 32'hDEAD_BEEF;
        end
        else if (shift_dr && (ir_hold_reg == INSTR_IDCODE)) begin
            idcode_shift <= {tdi, idcode_shift[31:1]};
        end
    end

    //-------------------------------------------------------------------------
    // BYPASS / CLAMP single-bit register (always loads 0 on capture per std)
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end
        else if (capture_dr && ((ir_hold_reg == INSTR_BYPASS) ||
                                (ir_hold_reg == INSTR_CLAMP)  ||
                                ((ir_hold_reg != INSTR_EXTEST) &&
                                 (ir_hold_reg != INSTR_SAMPLE) &&
                                 (ir_hold_reg != INSTR_IDCODE) &&
                                 (ir_hold_reg != INSTR_UTDR)))) begin
            bypass_reg <= 1'b0;
        end
        else if (shift_dr && ((ir_hold_reg != INSTR_EXTEST) &&
                              (ir_hold_reg != INSTR_SAMPLE) &&
                              (ir_hold_reg != INSTR_IDCODE) &&
                              (ir_hold_reg != INSTR_UTDR))) begin
            bypass_reg <= tdi;
        end
    end

    //-------------------------------------------------------------------------
    // User TDR select
    //-------------------------------------------------------------------------
    assign tdr_select = (ir_hold_reg == INSTR_UTDR);

    //-------------------------------------------------------------------------
    // TDO data-path mux (combinational selection)
    //-------------------------------------------------------------------------
    logic tdo_data;
    always_comb begin
        if (current_state == SHIFT_IR) begin
            tdo_data = ir_shift_reg[0];
        end
        else if (current_state == SHIFT_DR) begin
            unique case (ir_hold_reg)
                INSTR_EXTEST : tdo_data = bsr_tdo;
                INSTR_SAMPLE : tdo_data = bsr_tdo;
                INSTR_IDCODE : tdo_data = idcode_shift[0];
                INSTR_UTDR   : tdo_data = tdr_tdo;
                default      : tdo_data = bypass_reg; // BYPASS, CLAMP, etc.
            endcase
        end
        else begin
            tdo_data = 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // TDO output enable: active during SHIFT_DR and SHIFT_IR
    //-------------------------------------------------------------------------
    assign tdo_en = shift_dr | shift_ir;

    //-------------------------------------------------------------------------
    // TDO launched on negedge TCK (per IEEE 1149.1)
    //-------------------------------------------------------------------------
    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tdo <= 1'b0;
        end
        else begin
            tdo <= tdo_data;
        end
    end

endmodule : tap_controller
```
