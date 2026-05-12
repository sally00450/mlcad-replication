# Third-DUT Spec-Locked Prompts (AXI4-Lite)

## PS_AXI -- axi_lite_regs (spec-locked, AXI4-Lite slave)

Generate a SystemVerilog module called `axi_lite_regs` implementing a
minimal AXI4-Lite slave that hosts four 32-bit registers. The slave has
a single clock (`aclk`, rising-edge) and a single asynchronous
active-low reset (`aresetn`). All four registers reset to 32'h0.

Requirements:
- AXI4-Lite single-beat handshaking on all five channels (AW, W, B,
  AR, R). Each VALID/READY pair follows the standard AXI handshake
  (xfer happens on a cycle where VALID & READY are both high).
- Address map (byte addresses, using AWADDR/ARADDR[3:2] to select the
  word):
    * 0x00 -> reg0
    * 0x04 -> reg1
    * 0x08 -> reg2
    * 0x0C -> reg3
  Any address whose upper bits (AWADDR/ARADDR[31:4]) are non-zero is
  out-of-range.
- On a write, honor `wstrb[3:0]` per-byte: byte `b` of the addressed
  register is updated only when `wstrb[b]==1`. Unselected bytes keep
  their previous value.
- After a successful in-range write, assert `bvalid` with `bresp=2'b00`
  (OKAY). After an out-of-range write, assert `bvalid` with
  `bresp=2'b10` (SLVERR) and do not modify any register.
- After a successful in-range read, drive `rdata` with the register
  contents and `rresp=2'b00` (OKAY). After an out-of-range read, drive
  `rdata=32'h0` and `rresp` EITHER `2'b00` OR `2'b10`; the testbench
  accepts either.
- Reset clears all four registers, all output VALID signals, and all
  internal state.

Target ~80 lines, synthesizable SystemVerilog for VCS. Return ONLY
SystemVerilog code in a single ```systemverilog``` code block. No prose
outside the code block.

PORT CONTRACT (MANDATORY - non-negotiable):
The module MUST declare exactly these ports, with exactly these names,
directions, and widths. Do not rename. Do not add extra ports. Do not
reorder. Any deviation makes the response invalid.

    module axi_lite_regs (
        input  logic        aclk,
        input  logic        aresetn,
        // Write address channel
        input  logic [31:0] awaddr,
        input  logic        awvalid,
        output logic        awready,
        // Write data channel
        input  logic [31:0] wdata,
        input  logic [3:0]  wstrb,
        input  logic        wvalid,
        output logic        wready,
        // Write response channel
        output logic [1:0]  bresp,
        output logic        bvalid,
        input  logic        bready,
        // Read address channel
        input  logic [31:0] araddr,
        input  logic        arvalid,
        output logic        arready,
        // Read data channel
        output logic [31:0] rdata,
        output logic [1:0]  rresp,
        output logic        rvalid,
        input  logic        rready
    );
