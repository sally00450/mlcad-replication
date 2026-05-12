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

    logic        aw_captured, w_captured;
    logic [31:0] aw_addr_q;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    integer i;

    // Write logic
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            awready      <= 1'b0;
            wready       <= 1'b0;
            bvalid       <= 1'b0;
            bresp        <= 2'b00;
            aw_captured  <= 1'b0;
            w_captured   <= 1'b0;
            aw_addr_q    <= 32'h0;
            w_data_q     <= 32'h0;
            w_strb_q     <= 4'h0;
            for (i = 0; i < 4; i = i + 1) regs[i] <= 32'h0;
        end else begin
            // AW handshake
            if (!aw_captured && !bvalid) begin
                awready <= 1'b1;
                if (awready && awvalid) begin
                    aw_addr_q   <= awaddr;
                    aw_captured <= 1'b1;
                    awready     <= 1'b0;
                end
            end else begin
                awready <= 1'b0;
            end

            // W handshake
            if (!w_captured && !bvalid) begin
                wready <= 1'b1;
                if (wready && wvalid) begin
                    w_data_q   <= wdata;
                    w_strb_q   <= wstrb;
                    w_captured <= 1'b1;
                    wready     <= 1'b0;
                end
            end else begin
                wready <= 1'b0;
            end

            // Commit write when both captured
            if (aw_captured && w_captured && !bvalid) begin
                if (|aw_addr_q[31:4]) begin
                    bresp <= 2'b10;
                end else begin
                    bresp <= 2'b00;
                    for (i = 0; i < 4; i = i + 1) begin
                        if (w_strb_q[i])
                            regs[aw_addr_q[3:2]][i*8 +: 8] <= w_data_q[i*8 +: 8];
                    end
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end

            // B handshake
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                bresp  <= 2'b00;
            end
        end
    end

    // Read logic
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
        end else begin
            if (!rvalid && !arready) begin
                arready <= 1'b1;
            end else if (arready && arvalid) begin
                arready <= 1'b0;
                rvalid  <= 1'b1;
                if (|araddr[31:4]) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end
            end

            if (rvalid && rready) begin
                rvalid <= 1'b0;
                rdata  <= 32'h0;
                rresp  <= 2'b00;
            end
        end
    end

endmodule
```