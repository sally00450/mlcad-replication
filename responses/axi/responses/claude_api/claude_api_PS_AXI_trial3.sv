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

    // Write FSM
    logic        aw_captured, w_captured;
    logic [31:0] aw_addr_q;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    assign awready = !aw_captured && !bvalid;
    assign wready  = !w_captured  && !bvalid;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            regs[0] <= 32'h0;
            regs[1] <= 32'h0;
            regs[2] <= 32'h0;
            regs[3] <= 32'h0;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= 32'h0;
            w_data_q    <= 32'h0;
            w_strb_q    <= 4'h0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
        end else begin
            // Capture AW
            if (awvalid && awready) begin
                aw_addr_q   <= awaddr;
                aw_captured <= 1'b1;
            end
            // Capture W
            if (wvalid && wready) begin
                w_data_q   <= wdata;
                w_strb_q   <= wstrb;
                w_captured <= 1'b1;
            end
            // Perform write when both captured and no pending response
            if (!bvalid && (aw_captured || (awvalid && awready)) &&
                           (w_captured  || (wvalid  && wready ))) begin
                logic [31:0] a;
                logic [31:0] d;
                logic [3:0]  s;
                a = aw_captured ? aw_addr_q : awaddr;
                d = w_captured  ? w_data_q  : wdata;
                s = w_captured  ? w_strb_q  : wstrb;
                if (|a[31:4]) begin
                    bresp <= 2'b10;
                end else begin
                    logic [1:0] idx;
                    idx = a[3:2];
                    if (s[0]) regs[idx][ 7: 0] <= d[ 7: 0];
                    if (s[1]) regs[idx][15: 8] <= d[15: 8];
                    if (s[2]) regs[idx][23:16] <= d[23:16];
                    if (s[3]) regs[idx][31:24] <= d[31:24];
                    bresp <= 2'b00;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end
            // Clear bvalid on handshake
            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
        end
    end

    // Read FSM
    assign arready = !rvalid;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
            rresp  <= 2'b00;
            rdata  <= 32'h0;
        end else begin
            if (arvalid && arready) begin
                if (|araddr[31:4]) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[araddr[3:2]];
                    rresp <= 2'b00;
                end
                rvalid <= 1'b1;
            end else if (rvalid && rready) begin
                rvalid <= 1'b0;
            end
        end
    end

endmodule
```