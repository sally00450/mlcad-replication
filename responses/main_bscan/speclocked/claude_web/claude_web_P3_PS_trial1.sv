```systemverilog
//-----------------------------------------------------------------------------
// Module      : tap_controller
// Description : IEEE 1149.1 JTAG TAP Controller
//               - 16-state TAP FSM
//               - 4-bit Instruction Register (IR)
//               - 32-bit IDCODE shift register (0xDEADBEEF)
//               - 1-bit BYPASS register (shared with CLAMP)
//               - TDO launched on negedge TCK
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
    // TAP FSM State Encoding (16 states)
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
    } tap_state_t;

    tap_state_t current_state, next_state;

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
    logic [3:0]  ir_shift;       // IR shift stage
    logic [3:0]  ir_hold;        // IR hold (current effective instruction)
    logic [31:0] idcode_shift;   // IDCODE shift register
    logic        bypass_reg;     // 1-bit BYPASS / CLAMP register

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
    // FSM: next-state logic (per IEEE 1149.1 standard transitions)
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
    // Decoded state outputs
    //-------------------------------------------------------------------------
    assign capture_dr = (current_state == CAPTURE_DR);
    assign shift_dr   = (current_state == SHIFT_DR);
    assign update_dr  = (current_state == UPDATE_DR);
    assign capture_ir = (current_state == CAPTURE_IR);
    assign shift_ir   = (current_state == SHIFT_IR);
    assign update_ir  = (current_state == UPDATE_IR);

    //-------------------------------------------------------------------------
    // Instruction Register
    //   - Capture-IR : load fixed pattern 4'b0001 (LSB=1 per spec)
    //   - Shift-IR   : shift right, MSB <- TDI
    //   - Update-IR  : transfer shift register to hold register
    //   - TLR        : reset hold register to IDCODE
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift <= 4'b0001;
            ir_hold  <= INSTR_IDCODE;
        end
        else begin
            unique case (current_state)
                TEST_LOGIC_RESET: begin
                    ir_shift <= 4'b0001;
                    ir_hold  <= INSTR_IDCODE;
                end
                CAPTURE_IR: begin
                    ir_shift <= 4'b0001;   // mandatory '01' in two LSBs
                end
                SHIFT_IR: begin
                    ir_shift <= {tdi, ir_shift[3:1]};
                end
                UPDATE_IR: begin
                    ir_hold  <= ir_shift;
                end
                default: begin
                    // hold values
                end
            endcase
        end
    end

    assign ir_reg_out = ir_hold;

    //-------------------------------------------------------------------------
    // IDCODE Shift Register (32-bit, 0xDEADBEEF)
    //   - Capture-DR (when IDCODE selected): parallel-load 0xDEADBEEF
    //   - Shift-DR   (when IDCODE selected): shift right, MSB <- TDI
    //   - On TLR : reload IDCODE value
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift <= 32'hDEAD_BEEF;
        end
        else begin
            if (current_state == TEST_LOGIC_RESET) begin
                idcode_shift <= 32'hDEAD_BEEF;
            end
            else if (current_state == CAPTURE_DR && ir_hold == INSTR_IDCODE) begin
                idcode_shift <= 32'hDEAD_BEEF;
            end
            else if (current_state == SHIFT_DR && ir_hold == INSTR_IDCODE) begin
                idcode_shift <= {tdi, idcode_shift[31:1]};
            end
        end
    end

    //-------------------------------------------------------------------------
    // BYPASS / CLAMP 1-bit register
    //   - Capture-DR loads 0 (per spec)
    //   - Shift-DR shifts TDI in
    //   - Used when instruction is BYPASS, CLAMP, or any unimplemented
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end
        else begin
            if (current_state == CAPTURE_DR) begin
                // BYPASS register always captures 0 in Capture-DR
                if ((ir_hold != INSTR_IDCODE) &&
                    (ir_hold != INSTR_EXTEST) &&
                    (ir_hold != INSTR_SAMPLE) &&
                    (ir_hold != INSTR_UTDR)) begin
                    bypass_reg <= 1'b0;
                end
            end
            else if (current_state == SHIFT_DR) begin
                if ((ir_hold != INSTR_IDCODE) &&
                    (ir_hold != INSTR_EXTEST) &&
                    (ir_hold != INSTR_SAMPLE) &&
                    (ir_hold != INSTR_UTDR)) begin
                    bypass_reg <= tdi;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // User TDR select (asserted when current instruction is UTDR)
    //-------------------------------------------------------------------------
    assign tdr_select = (ir_hold == INSTR_UTDR);

    //-------------------------------------------------------------------------
    // TDO output enable - asserted only during SHIFT_DR or SHIFT_IR
    //-------------------------------------------------------------------------
    assign tdo_en = shift_dr | shift_ir;

    //-------------------------------------------------------------------------
    // TDO source mux (combinational)
    //-------------------------------------------------------------------------
    logic tdo_mux;

    always_comb begin
        tdo_mux = 1'b0;
        if (current_state == SHIFT_IR) begin
            tdo_mux = ir_shift[0];
        end
        else if (current_state == SHIFT_DR) begin
            unique case (ir_hold)
                INSTR_EXTEST,
                INSTR_SAMPLE : tdo_mux = bsr_tdo;
                INSTR_IDCODE : tdo_mux = idcode_shift[0];
                INSTR_UTDR   : tdo_mux = tdr_tdo;
                INSTR_BYPASS,
                INSTR_CLAMP  : tdo_mux = bypass_reg;
                default      : tdo_mux = bypass_reg;
            endcase
        end
        else begin
            tdo_mux = 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // TDO launched on NEGEDGE TCK (per IEEE 1149.1)
    //-------------------------------------------------------------------------
    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n)
            tdo <= 1'b0;
        else
            tdo <= tdo_mux;
    end

endmodule
```
