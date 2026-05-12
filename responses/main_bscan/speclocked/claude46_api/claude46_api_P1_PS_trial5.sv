

```systemverilog
// =============================================================================
// IEEE 1149.1 Boundary Scan - Behavioral Pad Models
// Target: SystemVerilog IEEE 1800-2017
// =============================================================================

// -----------------------------------------------------------------------------
// pad_input: Transparent input pad
// Buffers the signal from the chip boundary (pad_pin) into the core (core_data)
// -----------------------------------------------------------------------------
module pad_input (
    input  logic pad_pin,
    output logic core_data
);

    assign core_data = pad_pin;

endmodule

// -----------------------------------------------------------------------------
// pad_output: Tristate output pad
// When oe=1, pad_pin drives core_data; when oe=0, pad_pin is high-impedance
// -----------------------------------------------------------------------------
module pad_output (
    input  logic core_data,
    input  logic oe,
    output logic pad_pin
);

    assign pad_pin = oe ? core_data : 1'bz;

endmodule
```