```systemverilog
/**
 * IEEE 1149.1 BC_1 Boundary Scan Cell
 * 
 * Implements a standard BC_1 boundary scan cell with an input capture/shift
 * register and an output update latch.
 */
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

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    logic capture_reg;
    logic update_reg;

    //--------------------------------------------------------------------------
    // Capture/Shift Register
    //--------------------------------------------------------------------------
    // Synchronous to the positive edge of TCK.
    // Captures parallel data when capture_dr is high.
    // Shifts serial data when shift_dr is high.
    // Retains current state otherwise.
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end
        else if (shift_dr) begin
            capture_reg <= serial_in;
        end
    end

    //--------------------------------------------------------------------------
    // Update Latch/Register
    //--------------------------------------------------------------------------
    // Synchronous to the negative edge of TCK.
    // Updates the parallel output latch from the capture register
    // when update_dr is high.
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    
    // Serial output is directly driven by the capture register
    assign serial_out = capture_reg;

    // Parallel output multiplexer:
    // If mode == 1, drive the boundary scan test data (update_reg)
    // If mode == 0, pass through the normal system data (data_in)
    assign data_out = mode ? update_reg : data_in;

endmodule
```
