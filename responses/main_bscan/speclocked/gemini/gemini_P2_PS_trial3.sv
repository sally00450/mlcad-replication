```systemverilog
`timescale 1ns / 1ps

// ============================================================================
// Module      : bsc_cell
// Description : IEEE 1149.1 BC_1 Boundary Scan Cell
// 
// This module implements a standard BC_1 boundary scan cell as defined by 
// the IEEE 1149.1 JTAG standard. It contains two primary registers:
// 1. Capture Register (Shift Register) - Clocked on positive edge of TCK.
// 2. Update Register (Shadow Latch) - Clocked on negative edge of TCK.
// ============================================================================

module bsc_cell (
    // JTAG Clock and Control Signals
    input  logic tck,
    input  logic shift_dr,
    input  logic capture_dr,
    input  logic update_dr,
    input  logic mode,
    
    // Serial Data Path (Shift Path)
    input  logic serial_in,
    output logic serial_out,
    
    // Parallel Data Path (System Path)
    input  logic data_in,
    output logic data_out
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    
    logic capture_reg;
    logic update_reg;

    // ========================================================================
    // Capture Register (Shift Register)
    // ========================================================================
    // Captures data from the parallel input or shifts data from the serial
    // input on the rising edge of TCK. Priority is given to capture.
    
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end else if (shift_dr) begin
            capture_reg <= serial_in;
        end else begin
            // Hold state when not capturing or shifting
            capture_reg <= capture_reg;
        end
    end

    // ========================================================================
    // Update Register (Shadow Register)
    // ========================================================================
    // Latches the data from the capture register on the falling edge of TCK
    // to prevent race conditions during the UPDATE state.
    
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end else begin
            // Hold state when not updating
            update_reg <= update_reg;
        end
    end

    // ========================================================================
    // Output Assignments
    // ========================================================================
    
    // The serial output is continuously driven by the capture register
    // to allow daisy-chaining multiple boundary scan cells.
    assign serial_out = capture_reg;

    // The parallel data output is selected by the mode signal.
    // If mode == 1, the cell drives the update register value (test mode).
    // If mode == 0, the cell passes through the system data (normal mode).
    assign data_out = mode ? update_reg : data_in;

endmodule
```
