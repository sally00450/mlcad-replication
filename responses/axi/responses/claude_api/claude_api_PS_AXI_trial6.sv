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
    logic        aw_captured;
    logic        w_captured;
    logic [31:0] aw_addr_r;
    logic [31:0] w_data_r;
    logic [3:0]  w_strb_r;

    // Read state
    logic [31:0] ar_addr_r;

    assign awready = !aw_captured && aresetn;
    assign wready  = !w_captured  && aresetn;
    assign arready = !rvalid && aresetn;

    wire aw_hs = awvalid && awready;
    wire w_hs  = wvalid  && wready;
    wire ar_hs = arvalid && arready;

    wire do_write = aw_captured && w_captured && !bvalid;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            regs[0] <= 32'h0;
            regs[1] <= 32'h0;
            regs[2] <= 32'h0;
            regs[3] <= 32'h0;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_r   <= 32'h0;
            w_data_r    <= 32'h0;
            w_strb_r    <= 4'h0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
            rvalid      <= 1'b0;
            rdata       <= 32'h0;
            rresp       <= 2'b00;
            ar_addr_r   <= 32'h0;
        end else begin
            // Capture AW
            if (aw_hs) begin
                aw_addr_r   <= awaddr;
                aw_captured <= 1'b1;
            end
            // Capture W
            if (w_hs) begin
                w_data_r   <= wdata;
                w_strb_r   <= wstrb;
                w_captured <= 1'b1;
            end
            // Perform write and issue B
            if (do_write) begin
                if (|aw_addr_r[31:4]) begin
                    bresp <= 2'b10;
                end else begin
                    logic [1:0] idx;
                    idx = aw_addr_r[3:2];
                    if (w_strb_r[0]) regs[idx][7:0]   <= w_data_r[7:0];
                    if (w_strb_r[1]) regs[idx][15:8]  <= w_data_r[15:8];
                    if (w_strb_r[2]) regs[idx][23:16] <= w_data_r[23:16];
                    if (w_strb_r[3]) regs[idx][31:24] <= w_data_r[31:24];
                    bresp <= 2'b00;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end
            // B handshake
            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
            // Read
            if (ar_hs) begin
                ar_addr_r <= araddr;
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