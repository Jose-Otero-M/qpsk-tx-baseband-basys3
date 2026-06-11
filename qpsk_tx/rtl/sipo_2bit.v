module sipo_2bit (    
    input  wire clk,
    input  wire rst,

    input  wire bit_in,
    input  wire bit_valid,   // Strobe: bit_in is valid this cycle.

    output reg  [1:0] sym_bits,
    output reg        sym_valid_stb
);
    reg  have_1bit;
    reg  b0;

    always @(posedge clk) begin
        if (rst) begin
            have_1bit <= 1'b0;
            b0        <= 1'b0;
            sym_bits  <= 2'b00;
            sym_valid_stb <= 1'b0;
        end else begin
            sym_valid_stb <= 1'b0;

            if (bit_valid) begin
                if (!have_1bit) begin
                    b0        <= bit_in;   // First bit captured.
                    have_1bit <= 1'b1;
                end else begin
                    // Second bit captured => form symbol.
                    sym_bits  <= {b0, bit_in}; // sym_bits[1]=first, [0]=second (define your convention) LSB or MSB first.
                    sym_valid_stb <= 1'b1;
                    have_1bit <= 1'b0;
                end
            end
        end
    end
endmodule
