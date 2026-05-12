

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

    // Capture register (shift register) — clocked on posedge TCK
    logic capture_reg;

    // Update register — latched on negedge TCK
    logic update_reg;

    // ----------------------------------------------------------------
    // Capture / Shift register
    //   Priority: capture_dr > shift_dr (per IEEE 1149.1 BC_1 spec)
    //   On posedge TCK:
    //     - If capture_dr is asserted, sample data_in (parallel capture)
    //     - Else if shift_dr is asserted, sample serial_in (serial shift)
    //     - Otherwise, hold current value
    // ----------------------------------------------------------------
    always_ff @(posedge tck) begin
        if (capture_dr) begin
            capture_reg <= data_in;
        end else if (shift_dr) begin
            capture_reg <= serial_in;
        end
    end

    // ----------------------------------------------------------------
    // Update register
    //   On negedge TCK:
    //     - If update_dr is asserted, latch the capture register value
    //     - Otherwise, hold current value
    // ----------------------------------------------------------------
    always_ff @(negedge tck) begin
        if (update_dr) begin
            update_reg <= capture_reg;
        end
    end

    // ----------------------------------------------------------------
    // Serial output — always driven by the capture register
    // ----------------------------------------------------------------
    assign serial_out = capture_reg;

    // ----------------------------------------------------------------
    // Output mux
    //   mode = 0 : system data passes through (data_in)
    //   mode = 1 : boundary scan controlled output (update_reg)
    // ----------------------------------------------------------------
    assign data_out = mode ? update_reg : data_in;

endmodule
```