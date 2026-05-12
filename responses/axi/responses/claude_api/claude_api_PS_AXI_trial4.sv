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

    // Read state
    logic [31:0] ar_addr_q;
    logic        ar_captured;

    // Write handshakes
    assign awready = !aw_captured;
    assign wready  = !w_captured;

    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid  && wready;
    wire b_fire  = bvalid  && bready;

    wire aw_have = aw_captured || aw_fire;
    wire w_have  = w_captured  || w_fire;

    wire [31:0] eff_awaddr = aw_captured ? aw_addr_q : awaddr;
    wire [31:0] eff_wdata  = w_captured  ? w_data_q  : wdata;
    wire [3:0]  eff_wstrb  = w_captured  ? w_strb_q  : wstrb;

    wire        w_oor      = |eff_awaddr[31:4];
    wire [1:0]  w_index    = eff_awaddr[3:2];

    // Read handshakes
    assign arready = !ar_captured && !rvalid;
    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid  && rready;

    wire [31:0] eff_araddr = ar_captured ? ar_addr_q : araddr;
    wire        r_oor      = |eff_araddr[31:4];
    wire [1:0]  r_index    = eff_araddr[3:2];

    integer i;
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            for (i = 0; i < 4; i = i + 1) regs[i] <= 32'h0;
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            aw_addr_q   <= 32'h0;
            w_data_q    <= 32'h0;
            w_strb_q    <= 4'h0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
            ar_captured <= 1'b0;
            ar_addr_q   <= 32'h0;
            rvalid      <= 1'b0;
            rresp       <= 2'b00;
            rdata       <= 32'h0;
        end else begin
            // Capture AW
            if (aw_fire) begin
                aw_addr_q   <= awaddr;
                aw_captured <= 1'b1;
            end
            // Capture W
            if (w_fire) begin
                w_data_q   <= wdata;
                w_strb_q   <= wstrb;
                w_captured <= 1'b1;
            end

            // Perform write when both available and no outstanding b
            if (aw_have && w_have && !bvalid) begin
                if (!w_oor) begin
                    if (eff_wstrb[0]) regs[w_index][7:0]   <= eff_wdata[7:0];
                    if (eff_wstrb[1]) regs[w_index][15:8]  <= eff_wdata[15:8];
                    if (eff_wstrb[2]) regs[w_index][23:16] <= eff_wdata[23:16];
                    if (eff_wstrb[3]) regs[w_index][31:24] <= eff_wdata[31:24];
                    bresp <= 2'b00;
                end else begin
                    bresp <= 2'b10;
                end
                bvalid      <= 1'b1;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end

            if (b_fire) begin
                bvalid <= 1'b0;
            end

            // Read
            if (ar_fire) begin
                ar_addr_q   <= araddr;
                ar_captured <= 1'b1;
            end

            if ((ar_captured || ar_fire) && !rvalid) begin
                if (r_oor) begin
                    rdata <= 32'h0;
                    rresp <= 2'b10;
                end else begin
                    rdata <= regs[r_index];
                    rresp <= 2'b00;
                end
                rvalid      <= 1'b1;
                ar_captured <= 1'b0;
            end

            if (r_fire) begin
                rvalid <= 1'b0;
            end
        end
    end

endmodule
```