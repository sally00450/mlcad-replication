```systemverilog
//-----------------------------------------------------------------------------
// Module      : tap_controller
// Description : IEEE 1149.1 (JTAG) Test Access Port (TAP) Controller
//               - 16-state TAP FSM
//               - 4-bit Instruction Register (IR) with shift/update
//               - 32-bit IDCODE data register (0xDEADBEEF)
//               - 1-bit BYPASS register (shared with CLAMP)
//               - User-defined data register hookup via tdr_select / tdr_tdo
//               - Boundary-scan register hookup via bsr_tdo
//               TDO is launched on the negative edge of TCK per spec.
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
    // TAP State Encoding (IEEE 1149.1 - 16 states)
    //-------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_TLR        = 4'h0, // Test-Logic-Reset
        S_RTI        = 4'h1, // Run-Test/Idle
        S_SEL_DR     = 4'h2, // Select-DR-Scan
        S_CAP_DR     = 4'h3, // Capture-DR
        S_SHIFT_DR   = 4'h4, // Shift-DR
        S_EXIT1_DR   = 4'h5, // Exit1-DR
        S_PAUSE_DR   = 4'h6, // Pause-DR
        S_EXIT2_DR   = 4'h7, // Exit2-DR
        S_UPDATE_DR  = 4'h8, // Update-DR
        S_SEL_IR     = 4'h9, // Select-IR-Scan
        S_CAP_IR     = 4'hA, // Capture-IR
        S_SHIFT_IR   = 4'hB, // Shift-IR
        S_EXIT1_IR   = 4'hC, // Exit1-IR
        S_PAUSE_IR   = 4'hD, // Pause-IR
        S_EXIT2_IR   = 4'hE, // Exit2-IR
        S_UPDATE_IR  = 4'hF  // Update-IR
    } tap_state_t;

    tap_state_t state, next_state;

    //-------------------------------------------------------------------------
    // Instruction Encoding (4-bit)
    //-------------------------------------------------------------------------
    localparam logic [3:0] INSTR_EXTEST = 4'b0010;
    localparam logic [3:0] INSTR_SAMPLE = 4'b0011;
    localparam logic [3:0] INSTR_CLAMP  = 4'b0110;
    localparam logic [3:0] INSTR_UTDR   = 4'b0111;
    localparam logic [3:0] INSTR_IDCODE = 4'b1110;
    localparam logic [3:0] INSTR_BYPASS = 4'b1111;

    //-------------------------------------------------------------------------
    // Internal storage
    //-------------------------------------------------------------------------
    logic [3:0]  ir_shift;       // IR shift register
    logic [3:0]  ir_hold;        // IR hold/parallel-output register
    logic [31:0] idcode_shift;   // IDCODE shift register
    logic        bypass_reg;     // 1-bit BYPASS / CLAMP register

    localparam logic [31:0] IDCODE_VALUE = 32'hDEADBEEF;

    //-------------------------------------------------------------------------
    // FSM : Next-state logic (per IEEE 1149.1)
    //-------------------------------------------------------------------------
    always_comb begin
        unique case (state)
            S_TLR       : next_state = tms ? S_TLR       : S_RTI;
            S_RTI       : next_state = tms ? S_SEL_DR    : S_RTI;
            S_SEL_DR    : next_state = tms ? S_SEL_IR    : S_CAP_DR;
            S_CAP_DR    : next_state = tms ? S_EXIT1_DR  : S_SHIFT_DR;
            S_SHIFT_DR  : next_state = tms ? S_EXIT1_DR  : S_SHIFT_DR;
            S_EXIT1_DR  : next_state = tms ? S_UPDATE_DR : S_PAUSE_DR;
            S_PAUSE_DR  : next_state = tms ? S_EXIT2_DR  : S_PAUSE_DR;
            S_EXIT2_DR  : next_state = tms ? S_UPDATE_DR : S_SHIFT_DR;
            S_UPDATE_DR : next_state = tms ? S_SEL_DR    : S_RTI;
            S_SEL_IR    : next_state = tms ? S_TLR       : S_CAP_IR;
            S_CAP_IR    : next_state = tms ? S_EXIT1_IR  : S_SHIFT_IR;
            S_SHIFT_IR  : next_state = tms ? S_EXIT1_IR  : S_SHIFT_IR;
            S_EXIT1_IR  : next_state = tms ? S_UPDATE_IR : S_PAUSE_IR;
            S_PAUSE_IR  : next_state = tms ? S_EXIT2_IR  : S_PAUSE_IR;
            S_EXIT2_IR  : next_state = tms ? S_UPDATE_IR : S_SHIFT_IR;
            S_UPDATE_IR : next_state = tms ? S_SEL_DR    : S_RTI;
            default     : next_state = S_TLR;
        endcase
    end

    //-------------------------------------------------------------------------
    // FSM : State register (posedge TCK, async active-low TRST_N)
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            state <= S_TLR;
        else
            state <= next_state;
    end

    //-------------------------------------------------------------------------
    // Decoded state outputs
    //-------------------------------------------------------------------------
    assign capture_dr = (state == S_CAP_DR);
    assign shift_dr   = (state == S_SHIFT_DR);
    assign update_dr  = (state == S_UPDATE_DR);
    assign capture_ir = (state == S_CAP_IR);
    assign shift_ir   = (state == S_SHIFT_IR);
    assign update_ir  = (state == S_UPDATE_IR);

    //-------------------------------------------------------------------------
    // Instruction Register
    //   - Capture-IR   : load fixed pattern 4'b0001 (LSB=1 per spec)
    //   - Shift-IR     : shift toward LSB, MSB <= TDI
    //   - Update-IR    : transfer shift -> hold (parallel output)
    //   - TLR          : reset hold to IDCODE
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_shift <= 4'b0001;
            ir_hold  <= INSTR_IDCODE;
        end
        else begin
            case (state)
                S_TLR : begin
                    ir_shift <= 4'b0001;
                    ir_hold  <= INSTR_IDCODE;
                end
                S_CAP_IR : begin
                    // Two LSBs must be "01" per IEEE 1149.1
                    ir_shift <= 4'b0001;
                end
                S_SHIFT_IR : begin
                    ir_shift <= {tdi, ir_shift[3:1]};
                end
                S_UPDATE_IR : begin
                    ir_hold  <= ir_shift;
                end
                default : begin
                    ir_shift <= ir_shift;
                    ir_hold  <= ir_hold;
                end
            endcase
        end
    end

    assign ir_reg_out = ir_hold;

    //-------------------------------------------------------------------------
    // IDCODE shift register
    //   - Capture-DR (when IDCODE selected) : parallel load 0xDEADBEEF
    //   - Shift-DR   (when IDCODE selected) : shift toward LSB, MSB <= TDI
    //   - On TLR, IDCODE selected, so reload value
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift <= IDCODE_VALUE;
        end
        else begin
            if (state == S_TLR) begin
                idcode_shift <= IDCODE_VALUE;
            end
            else if (capture_dr && (ir_hold == INSTR_IDCODE)) begin
                idcode_shift <= IDCODE_VALUE;
            end
            else if (shift_dr && (ir_hold == INSTR_IDCODE)) begin
                idcode_shift <= {tdi, idcode_shift[31:1]};
            end
        end
    end

    //-------------------------------------------------------------------------
    // BYPASS register (1-bit). Used for BYPASS, CLAMP, and as default
    // for any unrecognized instruction.
    //   - Capture-DR : load 0
    //   - Shift-DR   : shift TDI in
    //-------------------------------------------------------------------------
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end
        else begin
            if (capture_dr) begin
                // Always safe to clear on Capture-DR; selected only when
                // IR is not IDCODE/UTDR/EXTEST/SAMPLE.
                bypass_reg <= 1'b0;
            end
            else if (shift_dr) begin
                bypass_reg <= tdi;
            end
        end
    end

    //-------------------------------------------------------------------------
    // tdr_select : asserted when current (held) instruction is UTDR
    //-------------------------------------------------------------------------
    assign tdr_select = (ir_hold == INSTR_UTDR);

    //-------------------------------------------------------------------------
    // TDO output enable : driven only during shift states
    //-------------------------------------------------------------------------
    assign tdo_en = (state == S_SHIFT_DR) || (state == S_SHIFT_IR);

    //-------------------------------------------------------------------------
    // TDO source mux (combinational pre-flop value)
    //-------------------------------------------------------------------------
    logic tdo_next;
    always_comb begin
        tdo_next = 1'b0;
        if (state == S_SHIFT_IR) begin
            tdo_next = ir_shift[0];
        end
        else if (state == S_SHIFT_DR) begin
            unique case (ir_hold)
                INSTR_EXTEST,
                INSTR_SAMPLE : tdo_next = bsr_tdo;
                INSTR_IDCODE : tdo_next = idcode_shift[0];
                INSTR_UTDR   : tdo_next = tdr_tdo;
                INSTR_BYPASS,
                INSTR_CLAMP  : tdo_next = bypass_reg;
                default      : tdo_next = bypass_reg;
            endcase
        end
        else begin
            tdo_next = 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // TDO is launched on the NEGATIVE edge of TCK (per IEEE 1149.1)
    //-------------------------------------------------------------------------
    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n)
            tdo <= 1'b0;
        else
            tdo <= tdo_next;
    end

endmodule
```
