module SIPO_sampler_and_QPSK #(
    parameter integer MAPPER_OUT_W   = 16,           // Output width.
    parameter integer MAPPER_AMP     = 16'd23170,     // Amplitude <= (2^(W-1)-1) * sqrt(2); (2^14) * sqrt(2) 
                                                     // (2^14) avoids headroom, sqrt(2) for energy normalization.

    parameter integer SIPO_SAMPLER_ACC_W = 32,
    parameter integer CLK_FREQ_HZ        = 100_000_000,
    parameter integer SAMPLE_RATE_HZ     = 36_000,        // Input serial bit rate in bit/s.

    parameter integer OSR_ACC_W      = 32,
    
    parameter         FIR_COEF_FILE        = "rrc_taps_q15_energy.mem",
    parameter integer RRC_FILTER_SPS       = 4,
    parameter integer RRC_N_TAPS           = 33,
    parameter integer RRC_INPUT_W          = 16,
    parameter integer RRC_COEF_W           = 16,
    parameter integer RRC_OUT_W            = 16,
    parameter integer RRC_ACC_W            = 40,
    parameter integer RRC_SHIFT            = 15,
    parameter integer RRC_ROUND_TO_NEAREST = 1
    
    )
    (
    input wire clk,
    input wire rst,
    
    input  wire bit_in,
    
    output wire signed [RRC_OUT_W-1:0] rrc_i,
    output wire signed [RRC_OUT_W-1:0] rrc_q,
    output wire                valid_rrc_out_i,
    output wire                valid_rrc_out_q
    );
    
    wire bit_valid_stb;
    
    NCO_stb_on_overflow #(
        .ACC_W(SIPO_SAMPLER_ACC_W),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ)
    )u_bitstream_sampler(
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .freeze_acc(1'b0),
        .sample_en(bit_valid_stb)
    );
    
    top_QPSK_baseband_tx #(
        .MAPPER_OUT_W(MAPPER_OUT_W),
        .MAPPER_AMP(MAPPER_AMP),
        .OSR_ACC_W(OSR_ACC_W),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BIT_RATE_HZ(SAMPLE_RATE_HZ),
        .FIR_COEF_FILE(FIR_COEF_FILE),
        .RRC_FILTER_SPS(RRC_FILTER_SPS),
        .RRC_N_TAPS(RRC_N_TAPS),
        .RRC_INPUT_W(RRC_INPUT_W),
        .RRC_COEF_W(RRC_COEF_W),
        .RRC_OUT_W(RRC_OUT_W),
        .RRC_ACC_W(RRC_ACC_W),
        .RRC_SHIFT(RRC_SHIFT),
        .RRC_ROUND_TO_NEAREST(RRC_ROUND_TO_NEAREST)
    )u_QPSK(
        .clk(clk),
        .rst(rst),
        .bit_in(bit_in),
        .bit_valid(bit_valid_stb),
        .rrc_i(rrc_i),
        .rrc_q(rrc_q),
        .valid_rrc_out_i(valid_rrc_out_i),
        .valid_rrc_out_q(valid_rrc_out_q)
    );
    
endmodule
