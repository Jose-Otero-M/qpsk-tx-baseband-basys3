module top_QPSK_baseband_tx #(
    parameter integer MAPPER_OUT_W   = 16,           // Output width.
    parameter integer MAPPER_AMP     = 16'd23170,     // Amplitude <= (2^(W-1)-1) * sqrt(2); (2^14) * sqrt(2) 
                                                     // (2^14) avoids headroom, sqrt(2) for energy normalization.

    parameter integer OSR_ACC_W      = 32,
    parameter integer CLK_FREQ_HZ    = 100_000_000,
    parameter integer BIT_RATE_HZ    = 36_000,
    
    parameter         FIR_COEF_FILE  = "rrc_taps_q15_energy.mem",
    parameter integer RRC_FILTER_SPS = 4,
    
    parameter integer RRC_N_TAPS     = 33,
    parameter integer RRC_INPUT_W    = 16,
    parameter integer RRC_COEF_W     = 16,
    parameter integer RRC_OUT_W      = 16,
    parameter integer RRC_ACC_W      = 40,
    parameter integer RRC_SHIFT      = 15,
    parameter integer RRC_ROUND_TO_NEAREST = 1
    )
    
    (
    input wire clk,
    input wire rst,
    
    input  wire bit_in,
    input  wire bit_valid,
    
    output wire signed [RRC_OUT_W-1:0] rrc_i,
    output wire signed [RRC_OUT_W-1:0] rrc_q,
    output wire                valid_rrc_out_i,
    output wire                valid_rrc_out_q
    
    );
    
    localparam integer SYM_RATE_HZ        = BIT_RATE_HZ / 2;
    localparam integer RRC_SAMPLE_RATE_HZ = SYM_RATE_HZ * RRC_FILTER_SPS;
    
    wire [1:0] sym_bits;
    wire sym_valid_stb;
    wire signed [MAPPER_OUT_W-1:0] I_sym;
    wire signed [MAPPER_OUT_W-1:0] Q_sym;
    wire iq_valid_stb;
    wire stb_sample_at_Rs_SPS;
    wire signed [MAPPER_OUT_W-1:0] I_resampled;
    wire signed [MAPPER_OUT_W-1:0] Q_resampled;
    wire valid_iq_resampled;
    wire signed [RRC_INPUT_W-1:0] I_resampled_rrc;
    wire signed [RRC_INPUT_W-1:0] Q_resampled_rrc;

    assign I_resampled_rrc = $signed(I_resampled);
    assign Q_resampled_rrc = $signed(Q_resampled);

    initial begin
        if (BIT_RATE_HZ <= 0) begin
            $error("Invalid BIT_RATE_HZ=%0d. BIT_RATE_HZ must be > 0.", BIT_RATE_HZ);
            $fatal;
        end

        if ((BIT_RATE_HZ % 2) != 0) begin
            $error("Invalid BIT_RATE_HZ=%0d. QPSK requires an even bit rate so Rs = Rb/2 is integer.", BIT_RATE_HZ);
            $fatal;
        end

        if (RRC_FILTER_SPS < 1) begin
            $error("Invalid RRC_FILTER_SPS=%0d. SPS must be >= 1.", RRC_FILTER_SPS);
            $fatal;
        end
    end
    
    sipo_2bit u_sipo (
        .clk(clk), 
        .rst(rst),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .sym_bits(sym_bits),
        .sym_valid_stb(sym_valid_stb)
    );
    
    qpsk_mapper #(
        .MAPPER_OUT_W(MAPPER_OUT_W),
        .MAPPER_AMP(MAPPER_AMP))
        u_mapper(
            .clk(clk),
            .rst(rst),
            .sym_bits(sym_bits),
            .sym_valid_stb(sym_valid_stb),
            .I_sym(I_sym),
            .Q_sym(Q_sym),
            .iq_valid_stb(iq_valid_stb)
    );
    
    NCO_stb_on_overflow #(
        .ACC_W(OSR_ACC_W),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ(RRC_SAMPLE_RATE_HZ)
    )u_sampler_for_zero_stuffer_at_SPS(
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .freeze_acc(1'b0),
        .sample_en(stb_sample_at_Rs_SPS)
    );
    
    iq_zero_stuffer #(
        .DATA_W(MAPPER_OUT_W),
        .SPS(RRC_FILTER_SPS)
    )u_OSR_zero_stuffer(
        .clk(clk),
        .rst(rst),
        .sample_en(stb_sample_at_Rs_SPS),   // One-clock strobe at output sample rate: Fs = Rs * SPS
        .in_valid_stb(iq_valid_stb),        // One-clock strobe at symbol rate: Rs
        .I_sym_in(I_sym),
        .Q_sym_in(Q_sym),
        .I_out(I_resampled),
        .Q_out(Q_resampled),
        .out_valid_stb(valid_iq_resampled)
    );
    
    top_fir #(
        .NTAPS(RRC_N_TAPS),
        .XW(RRC_INPUT_W),
        .CW(RRC_COEF_W),
        .YW(RRC_OUT_W),
        .ACCW(RRC_ACC_W),
        .SHIFT(RRC_SHIFT),
        .ROUND_TO_NEAREST(RRC_ROUND_TO_NEAREST),
        .COEF_FILE(FIR_COEF_FILE)
    )u_RRC_I(
        .clk(clk),
        .rst(rst),
        .en(valid_iq_resampled),
        .x_in(I_resampled_rrc),
        .y_valid(valid_rrc_out_i),
        .y_out(rrc_i)
    );
    
    
    top_fir #(
        .NTAPS(RRC_N_TAPS),
        .XW(RRC_INPUT_W),
        .CW(RRC_COEF_W),
        .YW(RRC_OUT_W),
        .ACCW(RRC_ACC_W),
        .SHIFT(RRC_SHIFT),
        .ROUND_TO_NEAREST(RRC_ROUND_TO_NEAREST),
        .COEF_FILE(FIR_COEF_FILE)
    )u_RRC_Q(
        .clk(clk),
        .rst(rst),
        .en(valid_iq_resampled),
        .x_in(Q_resampled_rrc),
        .y_valid(valid_rrc_out_q),
        .y_out(rrc_q)
    );
endmodule
