```systemverilog
//-----------------------------------------------------------------------------
// Module: bsc_cell
// Description: IEEE 1149.1 BC_1 boundary scan cell.
//   - Capture flip-flop samples either the system data (data_in) when
//     capture_dr is asserted, or the scan chain input (serial_in) when
//     shift_dr is asserted, on the rising edge of TCK.
//   - Update flip-flop latches the capture register on the falling edge
//     of TCK when update_dr is asserted.
//   - serial_out always reflects the capture register (scan chain out).
//   - data_out is muxed between the system data path (data_in) and the
//     update register, controlled by mode (test/normal select).
//-----------------------------------------------------------------------------
module bsc_cell (
    input  logic tck,
    input  logic shift_dr,
    input  logic capture_dr,
    input  logic update_dr,
    input  logic mode,
    input  logic serial_in,
    output logic serial_out,
    input  logic data_in,
    output logic data_out
);

    // Internal state
    logic capture_reg;
    logic update_reg;

    //-------------------------------------------------------------------------
    // Capture / Shift register
    //   Posedge TCK:
    //     capture_dr has priority over shift_dr (per BC_1 convention).
    //     If neither control is asserted, the register holds its value.
    //-------------------------------------------------------------------------
    always_ff @(posedge tck) begin
        if (capture_dr)
            capture_reg <= data_in;
        else if (shift_dr)
            capture_reg <= serial_in;
    end

    //-------------------------------------------------------------------------
    // Update register
    //   Negedge TCK:
    //     When update_dr is asserted, latch the capture register value
    //     so the system output can be driven with stable scan data.
    //-------------------------------------------------------------------------
    always_ff @(negedge tck) begin
        if (update_dr)
            update_reg <= capture_reg;
    end

    //-------------------------------------------------------------------------
    // Scan chain output: always the capture register.
    //-------------------------------------------------------------------------
    assign serial_out = capture_reg;

    //-------------------------------------------------------------------------
    // System output mux:
    //   mode = 0 -> normal operation, pass data_in through.
    //   mode = 1 -> test mode, drive update register onto data_out.
    //-------------------------------------------------------------------------
    assign data_out = mode ? update_reg : data_in;

endmodule
```
