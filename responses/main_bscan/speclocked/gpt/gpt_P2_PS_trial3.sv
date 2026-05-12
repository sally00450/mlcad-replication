```systemverilog
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

    // BC_1 boundary scan cell registers
    logic capture_reg;
    logic update_reg;

    // Capture/Shift operation on rising edge of TCK
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end else if (shift_dr) begin
            capture_reg <= serial_in;
        end
        // otherwise hold value
    end

    // Update operation on falling edge of TCK
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
        // otherwise hold value
    end

    // Serial output is always the capture register
    always_comb begin
        serial_out = capture_reg;
    end

    // Output mux: normal mode passes data_in, test mode drives update_reg
    always_comb begin
        data_out = mode ? update_reg : data_in;
    end

endmodule
```
