module qpsk_mapper #(
    parameter integer MAPPER_OUT_W   = 16,           // Output width.
    parameter integer MAPPER_AMP     = 16'd23170     // Component amplitude for unit-energy QPSK in Q1.15:
                                                     // A = (2^(W-1)-1)/sqrt(2) ≈ 23170 for W = 16.
                                                     // (2^14) avoids headroom, sqrt(2) for energy normalization.
)(
    input  wire              clk,
    input  wire              rst,
    input  wire      [1:0]   sym_bits,
    input  wire              sym_valid_stb,

    output reg signed [MAPPER_OUT_W-1:0] I_sym,
    output reg signed [MAPPER_OUT_W-1:0] Q_sym,
    output reg                iq_valid_stb
);
    // Convenient signed constants.
    wire signed [MAPPER_OUT_W-1:0] Apos = MAPPER_AMP;
    wire signed [MAPPER_OUT_W-1:0] Aneg = -MAPPER_AMP;

    always @(posedge clk) begin
        if (rst) begin
            I_sym    <= {MAPPER_OUT_W{1'b0}};
            Q_sym    <= {MAPPER_OUT_W{1'b0}};
            iq_valid_stb <= 1'b0;
        end else begin
            iq_valid_stb <= 1'b0;
            
            if (sym_valid_stb) begin
                iq_valid_stb <= 1'b1;
                case (sym_bits)
                    2'b00: begin I_sym <= Aneg; Q_sym <= Aneg; end
                    2'b01: begin I_sym <= Aneg; Q_sym <= Apos; end
                    2'b11: begin I_sym <= Apos; Q_sym <= Apos; end
                    2'b10: begin I_sym <= Apos; Q_sym <= Aneg; end
                    default: begin 
                        I_sym <= {MAPPER_OUT_W{1'b0}};
                        Q_sym <= {MAPPER_OUT_W{1'b0}}; 
                    end
                endcase
            end
        end
    end
endmodule
