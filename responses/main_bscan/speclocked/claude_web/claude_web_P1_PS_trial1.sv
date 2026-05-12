```systemverilog
// IEEE 1149.1 Boundary Scan - Behavioral Pad Models
// Target: SystemVerilog IEEE 1800-2017, synthesizable

module pad_input (
    input  logic pad_pin,
    output logic core_data
);

    // Transparent input pad: buffers signal from chip boundary into core
    assign core_data = pad_pin;

endmodule : pad_input


module pad_output (
    input  logic core_data,
    input  logic oe,
    output logic pad_pin
);

    // Tristate output pad: drives core_data when oe=1, else high-Z
    assign pad_pin = oe ? core_data : 1'bz;

endmodule : pad_output
```
