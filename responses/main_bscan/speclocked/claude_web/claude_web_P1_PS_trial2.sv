```systemverilog
// IEEE 1149.1 Boundary Scan - Behavioral Pad Models
// Target: SystemVerilog IEEE 1800-2017, synthesizable

// Transparent input pad: buffers signal from chip boundary into the core
module pad_input (
    input  logic pad_pin,
    output logic core_data
);

    assign core_data = pad_pin;

endmodule : pad_input


// Tristate output pad: drives pad_pin with core_data when oe=1, else high-Z
module pad_output (
    input  logic core_data,
    input  logic oe,
    output logic pad_pin
);

    assign pad_pin = oe ? core_data : 1'bz;

endmodule : pad_output
```
