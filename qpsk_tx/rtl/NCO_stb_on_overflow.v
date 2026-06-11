module NCO_stb_on_overflow #(
    parameter integer ACC_W          = 32,
    parameter integer CLK_FREQ_HZ    = 100_000_000,
    parameter integer SAMPLE_RATE_HZ = 36_000)
    (
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire freeze_acc,
    output reg  sample_en
    );
    
    
    reg  [ACC_W-1:0] acc;
    wire [ACC_W:0]   acc_sum;
    
    // -------------------------------------------------------------------------
    // Parameter validation guards
    // -------------------------------------------------------------------------
    localparam VALID_ACC_W       = (ACC_W >= 1) && (ACC_W <= 63);
    localparam VALID_CLK_FREQ    = (CLK_FREQ_HZ > 0);
    localparam VALID_SAMPLE_RATE = (SAMPLE_RATE_HZ > 0) && (SAMPLE_RATE_HZ < CLK_FREQ_HZ);
    localparam VALID_CONFIG      = VALID_ACC_W && VALID_CLK_FREQ && VALID_SAMPLE_RATE;
    
    // -------------------------------------------------------------------------
    // 64-bit intermediate values to avoid overflow in constant arithmetic
    // -------------------------------------------------------------------------
    localparam [63:0] CLK_FREQ_64    = VALID_CLK_FREQ    ? CLK_FREQ_HZ    : 64'd1;
    localparam [63:0] SAMPLE_RATE_64 = VALID_SAMPLE_RATE ? SAMPLE_RATE_HZ : 64'd0;
    
    // Rounded numerator:
    // (SAMPLE_RATE_HZ * 2^ACC_W) + CLK_FREQ_HZ/2
    localparam [63:0] FCW_NUMERATOR =
        VALID_CONFIG ? ((SAMPLE_RATE_64 << ACC_W) + (CLK_FREQ_64 >> 1)) : 64'd0;
    
    localparam [63:0] FCW_64 =
        VALID_CONFIG ? (FCW_NUMERATOR / CLK_FREQ_64) : 64'd0;
    
    localparam [ACC_W-1:0] FCW = FCW_64[ACC_W-1:0];
    
    assign acc_sum = {1'b0, acc} + {1'b0, FCW}; // Concat + concat
    
    always @(posedge clk) begin
        if (rst) begin
            acc       <= {ACC_W{1'b0}};
            sample_en <= 1'b0;
        end 
        else if (en) begin
            acc       <= acc_sum[ACC_W-1:0];
            sample_en <= acc_sum[ACC_W];  // One-clock strobe on accumulator overflow
        end
        else begin
            if (freeze_acc) begin
                acc       <= acc;           // Freeze acc.
            end
            else begin
                acc       <= {ACC_W{1'b0}}; // Reset acc.
            end
            sample_en <= 1'b0;
        end
    end
    
    // -------------------------------------------------------------------------
    // Simulation/elaboration checks
    // -------------------------------------------------------------------------
    initial begin
        if (!VALID_ACC_W) begin
            $error("Invalid ACC_W=%0d. ACC_W must be in the range 1 to 63 for 64-bit intermediate arithmetic.", ACC_W);
            $fatal;
        end
        
        if (!VALID_CLK_FREQ) begin
            $error("Invalid CLK_FREQ_HZ=%0d. CLK_FREQ_HZ must be greater than zero.", CLK_FREQ_HZ);
            $fatal;
        end
        
        if (SAMPLE_RATE_HZ <= 0) begin
            $error("Invalid SAMPLE_RATE_HZ=%0d. SAMPLE_RATE_HZ must be greater than zero.", SAMPLE_RATE_HZ);
            $fatal;
        end
        
        if (SAMPLE_RATE_HZ >= CLK_FREQ_HZ) begin
            $error("Invalid SAMPLE_RATE_HZ=%0d. It must be lower than CLK_FREQ_HZ=%0d for this strobe generator.", SAMPLE_RATE_HZ, CLK_FREQ_HZ);
            $fatal;
        end
        
        if (FCW_64 == 0) begin
            $error("Computed FCW (Frequency Control Word) is zero. Increase ACC_W or SAMPLE_RATE_HZ.");
            $fatal;
        end
        
        $display("NCO_stb_on_overflow configuration:");
        $display("  ACC_W          = %0d", ACC_W);
        $display("  CLK_FREQ_HZ    = %0d", CLK_FREQ_HZ);
        $display("  SAMPLE_RATE_HZ = %0d", SAMPLE_RATE_HZ);
        $display("  FCW            = %0d", FCW_64);
    end 

endmodule