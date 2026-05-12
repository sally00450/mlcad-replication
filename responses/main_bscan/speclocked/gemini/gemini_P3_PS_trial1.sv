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

    // TAP States
    typedef enum logic [3:0] {
        TLR  = 4'h0, // Test-Logic-Reset
        RTI  = 4'h1, // Run-Test/Idle
        SDR  = 4'h2, // Select-DR-Scan
        CDR  = 4'h3, // Capture-DR
        SHDR = 4'h4, // Shift-DR
        E1DR = 4'h5, // Exit1-DR
        PDR  = 4'h6, // Pause-DR
        E2DR = 4'h7, // Exit2-DR
        UDR  = 4'h8, // Update-DR
        SIR  = 4'h9, // Select-IR-Scan
        CIR  = 4'hA, // Capture-IR
        SHIR = 4'hB, // Shift-IR
        E1IR = 4'hC, // Exit1-IR
        PIR  = 4'hD, // Pause-IR
        E2IR = 4'hE, // Exit2-IR
        UIR  = 4'hF  // Update-IR
    } tap_state_t;

    tap_state_t state, next_state;

    // Instructions
    localparam logic [3:0] 
        EXTEST = 4'b0010,
        SAMPLE = 4'b0011,
        CLAMP  = 4'b0110,
        UTDR   = 4'b0111,
        IDCODE = 4'b1110,
        BYPASS = 4'b1111;

    // Internal Registers
    logic [3:0]  ir_reg;
    logic [3:0]  ir_shift;
    logic [31:0] idcode_shift;
    logic        bypass_reg;
    
    // TDO internal signals
    logic tdo_int;
    logic tdo_en_int;

    // FSM State Register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n)
            state <= TLR;
        else
            state <= next_state;
    end

    // FSM Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            TLR:  next_state = tms ? TLR : RTI;
            RTI:  next_state = tms ? SDR : RTI;
            
            // DR Branch
            SDR:  next_state = tms ? SIR : CDR;
            CDR:  next_state = tms ? E1DR : SHDR;
            SHDR: next_state = tms ? E1DR : SHDR;
            E1DR: next_state = tms ? UDR : PDR;
            PDR:  next_state = tms ? E2DR : PDR;
            E2DR: next_state = tms ? UDR : SHDR;
            UDR:  next_state = tms ? SDR : RTI;
            
            // IR Branch
            SIR:  next_state = tms ? TLR : CIR;
            CIR:  next_state = tms ? E1IR : SHIR;
            SHIR: next_state = tms ? E1IR : SHIR;
            E1IR: next_state = tms ? UIR : PIR;
            PIR:  next_state = tms ? E2IR : PIR;
            E2IR: next_state = tms ? UIR : SHIR;
            UIR:  next_state = tms ? SDR : RTI;
            
            default: next_state = TLR;
        endcase
    end

    // FSM Outputs
    assign shift_dr   = (state == SHDR);
    assign capture_dr = (state == CDR);
    assign update_dr  = (state == UDR);
    assign shift_ir   = (state == SHIR);
    assign capture_ir = (state == CIR);
    assign update_ir  = (state == UIR);

    // Instruction Register (IR)
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            ir_reg   <= IDCODE;
            ir_shift <= 4'h0;
        end else begin
            if (state == TLR) begin
                ir_reg <= IDCODE;
            end else if (capture_ir) begin
                ir_shift <= 4'b0001; // JTAG spec requires LSBs to be 01
            end else if (shift_ir) begin
                ir_shift <= {tdi, ir_shift[3:1]};
            end else if (update_ir) begin
                ir_reg <= ir_shift;
            end
        end
    end

    assign ir_reg_out = ir_reg;
    assign tdr_select = (ir_reg == UTDR);

    // IDCODE Register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            idcode_shift <= 32'hDEADBEEF;
        end else if (state == TLR) begin
            idcode_shift <= 32'hDEADBEEF;
        end else if (capture_dr && ir_reg == IDCODE) begin
            idcode_shift <= 32'hDEADBEEF;
        end else if (shift_dr && ir_reg == IDCODE) begin
            idcode_shift <= {tdi, idcode_shift[31:1]};
        end
    end

    // BYPASS Register
    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            bypass_reg <= 1'b0;
        end else if (capture_dr) begin
            bypass_reg <= 1'b0;
        end else if (shift_dr) begin
            bypass_reg <= tdi;
        end
    end

    // TDO Internal Mux
    always_comb begin
        tdo_int = 1'b0;
        if (shift_ir) begin
            tdo_int = ir_shift[0];
        end else if (shift_dr) begin
            case (ir_reg)
                EXTEST, SAMPLE: tdo_int = bsr_tdo;
                IDCODE:         tdo_int = idcode_shift[0];
                UTDR:           tdo_int = tdr_tdo;
                default:        tdo_int = bypass_reg;
            endcase
        end
    end

    assign tdo_en_int = (shift_ir || shift_dr);

    // TDO Output Flop (launched on negedge TCK as per JTAG spec)
    always_ff @(negedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tdo    <= 1'b0;
            tdo_en <= 1'b0;
        end else begin
            tdo    <= tdo_int;
            tdo_en <= tdo_en_int;
        end
    end

endmodule
```
