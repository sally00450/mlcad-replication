//-----------------------------------------------------------------------------
// axi_lite_regs -- Reference AXI4-Lite slave with 4 x 32-bit registers.
// Address map (byte addr, AWADDR[5:2] selects word):
//   0x00 -> reg0
//   0x04 -> reg1
//   0x08 -> reg2
//   0x0C -> reg3
// Out-of-range addresses respond with SLVERR and RDATA=0.
// Single-beat handshaking per AXI4-Lite; awready/wready asserted together.
// Reset value for all 4 registers: 32'h0.
// wstrb supported for per-byte masking on writes.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

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

    // Internal register file
    logic [31:0] regs [0:3];

    // Latched write address (captured when awvalid & awready)
    logic [31:0] aw_addr_q;
    logic        aw_captured;
    logic        w_captured;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    // Write FSM
    typedef enum logic [1:0] {W_IDLE, W_WAIT, W_RESP} w_state_t;
    w_state_t w_state;

    // Read FSM
    typedef enum logic [0:0] {R_IDLE, R_RESP} r_state_t;
    r_state_t r_state;

    // Responses
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // --------- Write path ---------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_state     <= W_IDLE;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= '0;
            w_data_q    <= '0;
            w_strb_q    <= '0;
            bvalid      <= 1'b0;
            bresp       <= RESP_OKAY;
            awready     <= 1'b0;
            wready      <= 1'b0;
            for (int i = 0; i < 4; i++) regs[i] <= 32'h0;
        end else begin
            // Default single-cycle assertions
            awready <= 1'b0;
            wready  <= 1'b0;

            case (w_state)
                W_IDLE: begin
                    // Accept AW and W simultaneously or independently
                    if (awvalid && !aw_captured) begin
                        awready     <= 1'b1;
                        aw_addr_q   <= awaddr;
                        aw_captured <= 1'b1;
                    end
                    if (wvalid && !w_captured) begin
                        wready     <= 1'b1;
                        w_data_q   <= wdata;
                        w_strb_q   <= wstrb;
                        w_captured <= 1'b1;
                    end
                    if ((aw_captured || (awvalid && !aw_captured)) &&
                        (w_captured  || (wvalid  && !w_captured))) begin
                        w_state <= W_RESP;
                    end
                end
                W_RESP: begin
                    // Perform write, assert BVALID
                    if (aw_addr_q[31:4] != 28'h0) begin
                        bresp <= RESP_SLVERR;
                    end else begin
                        bresp <= RESP_OKAY;
                        for (int b = 0; b < 4; b++) begin
                            if (w_strb_q[b])
                                regs[aw_addr_q[3:2]][8*b +: 8] <= w_data_q[8*b +: 8];
                        end
                    end
                    bvalid <= 1'b1;
                    if (bvalid && bready) begin
                        bvalid      <= 1'b0;
                        aw_captured <= 1'b0;
                        w_captured  <= 1'b0;
                        w_state     <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // --------- Read path ---------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_state <= R_IDLE;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= RESP_OKAY;
        end else begin
            arready <= 1'b0;
            case (r_state)
                R_IDLE: begin
                    if (arvalid) begin
                        arready <= 1'b1;
                        if (araddr[31:4] != 28'h0) begin
                            rdata <= 32'h0;
                            rresp <= RESP_SLVERR;
                        end else begin
                            rdata <= regs[araddr[3:2]];
                            rresp <= RESP_OKAY;
                        end
                        rvalid  <= 1'b1;
                        r_state <= R_RESP;
                    end
                end
                R_RESP: begin
                    if (rvalid && rready) begin
                        rvalid  <= 1'b0;
                        r_state <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
