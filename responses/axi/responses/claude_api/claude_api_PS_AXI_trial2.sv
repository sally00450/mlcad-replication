```systemverilog
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

    logic [31:0] regs [0:3];

    // Write state
    logic        aw_captured, w_captured;
    logic [31:0] aw_addr_q;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            regs[0] <= 32'h0;
            regs[1] <= 32'h0;
            regs[2] <= 32'h0;
            regs[3] <= 32'h0;
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= 32'h0;
            w_data_q    <= 32'h0;
            w_strb_q    <= 4'h0;
        end else begin
            // Write address handshake
            if (!aw_captured && !bvalid) awready <= 1'b1;
            if (awready && awvalid) begin
                aw_addr_q   <= awaddr;
                aw_captured <= 1'b1;
                awready     <= 1'b0;
            end

            // Write data handshake
            if (!w_captured && !bvalid) wready <= 1'b1;
            if (wready && wvalid) begin
                w_data_q   <= wdata;
                w_strb_q   <= wstrb;
                w_captured <= 1'b1;
                wready     <= 1'b0;
            end

            // Perform write when both captured
            if (aw_captured && w_captured && !bvalid) begin
                if (|aw_addr_q[31:4]) begin
                    bresp <= 2'b10;
                end else begin
                    logic [1:0] idx;
                    idx = aw_addr_q[3:2];
                    if (w_strb_q[0]) regs[idx][7:0]   <= w_data_q[7:0];
                    if (w_strb_q[1]) regs[idx][15:8]  <= w_data_q[15:8];
                    if (w_strb_q[2]) regs[idx][23:16] <= w_data_q[23:16];
                    if (w_strb_q[3]) regs[idx][31:24] <= w_data_q[31:24];
                    bresp <= 2'b00;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end

            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end

            // Read channel
            if (!rvalid && !arready) arready <= 1'b1;
            if (arready && arvalid) begin
                arready <= 1'b0;
                if (|araddr[31:4]) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end
                rvalid <= 1'b1;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
            end
        end
    end

endmodule
```