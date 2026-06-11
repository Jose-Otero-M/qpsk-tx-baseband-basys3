module delay_line_M_words_N_bits #(
    parameter integer M_STAGES = 4,
    parameter integer N_BITS   = 16)
    
    (
    input  wire                          clk,
    input  wire                          rst,          // RST (ReSeT), synchronous.
    input  wire                          en,           // EN (ENable).
    input  wire signed [N_BITS-1:0]      data_in,
    output wire  [M_STAGES*N_BITS-1:0]   data_out_flat // data_out_flatten.        
    );

    initial begin
        if (M_STAGES <= 0) $error("M_STAGES must be > 0");
        if (N_BITS   <= 0) $error("N_BITS must be > 0");
    end
    
    reg signed [N_BITS-1:0] stage [0:M_STAGES-1];
    integer i;
        
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < M_STAGES; i = i + 1) begin
                stage[i] <= {N_BITS{1'b0}};
            end
        end else if (en) begin
            // Shift: stage <= (stage << N_BITS) | data_in;
            stage[0] <= data_in;
            for (i = 1; i < M_STAGES; i = i + 1) begin
                stage[i] <= stage[i-1];
            end 
        end
    end

    genvar j;
    generate
        for (j = 0; j < M_STAGES; j = j + 1) begin : OUTPUT // Block name 'OUTPUT'.
            assign data_out_flat[j*N_BITS +: N_BITS] = stage[j]; // Continuos assign inside the for loop.
                                                                 // For use outside the module: wire [N_BITS-1:0] stage_k = data_out_flat[k*N_BITS +: N_BITS];
        end
    endgenerate

endmodule
