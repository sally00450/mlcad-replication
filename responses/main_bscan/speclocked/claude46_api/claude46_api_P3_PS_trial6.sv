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

  // Instruction codes
  localparam logic [3:0] EXTEST = 4'b0010;
  localparam logic [3:0] SAMPLE = 4'b0011;
  localparam logic [3:0] CLAMP  = 4'b0110;
  localparam logic [3:0] UTDR   = 4'b0111;
  localparam logic [3:0] IDCODE = 4'b1110;
  localparam logic [3:0] BYPASS = 4'b1111;

  // FSM state encoding
  typedef enum logic [3:0] {
    TLR       = 4'h0,
    RTI       = 4'h1,
    SELECT_DR = 4'h2,
    CAPTURE_DR= 4'h3,
    SHIFT_DR  = 4'h4,
    EXIT1_DR  = 4'h5,
    PAUSE_DR  = 4'h6,
    EXIT2_DR  = 4'h7,
    UPDATE_DR = 4'h8,
    SELECT_IR = 4'h9,
    CAPTURE_IR= 4'hA,
    SHIFT_IR  = 4'hB,
    EXIT1_IR  = 4'hC,
    PAUSE_IR  = 4'hD,
    EXIT2_IR  = 4'hE,
    UPDATE_IR = 4'hF
  } state_t;

  state_t state, next_state;

  // IR registers
  logic [3:0] ir_shift;
  logic [3:0] ir_hold;

  // IDCODE shift register
  logic [31:0] idcode_reg;

  // BYPASS register
  logic bypass_reg;

  // TDO mux output (before negedge register)
  logic tdo_mux;
  logic tdo_en_next;

  // -------------------------------------------------------
  // FSM next-state logic
  // -------------------------------------------------------
  always_comb begin
    case (state)
      TLR:        next_state = tms ? TLR        : RTI;
      RTI:        next_state = tms ? SELECT_DR  : RTI;
      SELECT_DR:  next_state = tms ? SELECT_IR  : CAPTURE_DR;
      CAPTURE_DR: next_state = tms ? EXIT1_DR   : SHIFT_DR;
      SHIFT_DR:   next_state = tms ? EXIT1_DR   : SHIFT_DR;
      EXIT1_DR:   next_state = tms ? UPDATE_DR  : PAUSE_DR;
      PAUSE_DR:   next_state = tms ? EXIT2_DR   : PAUSE_DR;
      EXIT2_DR:   next_state = tms ? UPDATE_DR  : SHIFT_DR;
      UPDATE_DR:  next_state = tms ? SELECT_DR  : RTI;
      SELECT_IR:  next_state = tms ? TLR        : CAPTURE_IR;
      CAPTURE_IR: next_state = tms ? EXIT1_IR   : SHIFT_IR;
      SHIFT_IR:   next_state = tms ? EXIT1_IR   : SHIFT_IR;
      EXIT1_IR:   next_state = tms ? UPDATE_IR  : PAUSE_IR;
      PAUSE_IR:   next_state = tms ? EXIT2_IR   : PAUSE_IR;
      EXIT2_IR:   next_state = tms ? UPDATE_IR  : SHIFT_IR;
      UPDATE_IR:  next_state = tms ? SELECT_DR  : RTI;
      default:    next_state = TLR;
    endcase
  end

  // -------------------------------------------------------
  // State register (posedge TCK, async reset)
  // -------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      state <= TLR;
    else
      state <= next_state;
  end

  // -------------------------------------------------------
  // IR shift register and holding register
  // -------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ir_shift <= IDCODE;
      ir_hold  <= IDCODE;
    end else begin
      case (state)
        CAPTURE_IR: ir_shift <= 4'b0101; // Fixed capture pattern per IEEE 1149.1 (xx01)
        SHIFT_IR:   ir_shift <= {tdi, ir_shift[3:1]};
        EXIT1_IR,
        EXIT2_IR:   ir_shift <= ir_shift; // hold
        UPDATE_IR:  ir_hold  <= ir_shift;
        TLR:        ir_hold  <= IDCODE;
        default: ;
      endcase
    end
  end

  assign ir_reg_out = ir_hold;

  // -------------------------------------------------------
  // IDCODE shift register (32-bit)
  // -------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      idcode_reg <= 32'hDEADBEEF;
    end else begin
      if (state == CAPTURE_DR && ir_hold == IDCODE)
        idcode_reg <= 32'hDEADBEEF;
      else if (state == SHIFT_DR && ir_hold == IDCODE)
        idcode_reg <= {tdi, idcode_reg[31:1]};
    end
  end

  // -------------------------------------------------------
  // BYPASS register (1-bit)
  // -------------------------------------------------------
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      bypass_reg <= 1'b0;
    end else begin
      if (state == CAPTURE_DR && (ir_hold == BYPASS || ir_hold == CLAMP))
        bypass_reg <= 1'b0;
      else if (state == SHIFT_DR && (ir_hold == BYPASS || ir_hold == CLAMP))
        bypass_reg <= tdi;
    end
  end

  // -------------------------------------------------------
  // Output decode: state-based signals
  // -------------------------------------------------------
  assign shift_dr   = (state == SHIFT_DR);
  assign capture_dr = (state == CAPTURE_DR);
  assign update_dr  = (state == UPDATE_DR);
  assign shift_ir   = (state == SHIFT_IR);
  assign capture_ir = (state == CAPTURE_IR);
  assign update_ir  = (state == UPDATE_IR);

  // tdr_select
  assign tdr_select = (ir_hold == UTDR);

  // -------------------------------------------------------
  // TDO mux (combinational, before negedge flop)
  // -------------------------------------------------------
  always_comb begin
    tdo_mux = 1'b0;
    tdo_en_next = 1'b0;

    if (state == SHIFT_DR) begin
      tdo_en_next = 1'b1;
      case (ir_hold)
        EXTEST, SAMPLE: tdo_mux = bsr_tdo;
        IDCODE:         tdo_mux = idcode_reg[0];
        UTDR:           tdo_mux = tdr_tdo;
        default:        tdo_mux = bypass_reg;
      endcase
    end else if (state == SHIFT_IR) begin
      tdo_en_next = 1'b1;
      tdo_mux = ir_shift[0];
    end
  end

  // -------------------------------------------------------
  // TDO output register (negedge TCK)
  // -------------------------------------------------------
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo    <= 1'b0;
      tdo_en <= 1'b0;
    end else begin
      tdo    <= tdo_mux;
      tdo_en <= tdo_en_next;
    end
  end

endmodule
```