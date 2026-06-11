module top_fir #(
    parameter         COEF_FILE = "rrc_taps_q15_energy.mem",
    parameter integer NTAPS     = 33,
    parameter integer XW        = 16, // Input width
    parameter integer CW        = 16, // Coeff width (e.g., Q1.15)
    parameter integer YW        = 16, // Output width
    parameter integer ACCW      = 40, // Accumulator width
    parameter integer SHIFT     = 15, // Right shift after MAC (Q1.15 -> integer)
    parameter integer ROUND_TO_NEAREST = 1
    )
    
    ( 
    input wire clk,
    input wire rst,
    
    input wire en, // sample strobe/enable
    input wire signed [XW-1:0] x_in,
    
    output reg y_valid,
    output reg signed [YW-1:0] y_out
    );

    localparam integer DELAY_STAGES = NTAPS-1;
    wire [DELAY_STAGES*XW-1:0] output_delay_line_flat; 
    
    delay_line_M_words_N_bits #(.M_STAGES(DELAY_STAGES), .N_BITS(XW)
    ) u_delay_line(
        .clk(clk),
        .rst(rst),
        .en(en),
        .data_in(x_in),
        .data_out_flat(output_delay_line_flat)
    );

    // Unflat the delay line
    /////////////////////////
    reg signed [XW-1:0] xz [0:NTAPS-1];  // Delay line unflatten
     
    integer k;
    always @(*) begin
        xz[0] = x_in;
        for(k = 0; k < DELAY_STAGES; k=k+1) begin
           //xz[k] = output_delay_line_flat[k*XW +: XW];
           xz[k+1] = output_delay_line_flat[k*XW +: XW];
        end
    end    


    // Coefficient ROM with NTAPS locations, each CW bits wide.
    reg signed [CW-1:0] coef_array [0:NTAPS-1];
    integer c;
    
    initial begin
        if (NTAPS <= 0) begin
            $error("Invalid NTAPS=%0d. NTAPS must be > 0.", NTAPS);
            $fatal;
        end

        if (XW <= 0 || CW <= 0 || YW <= 0 || ACCW <= 0) begin
            $error("Invalid word widths. XW, CW, YW and ACCW must be > 0.");
            $fatal;
        end

        if (SHIFT < 0) begin
            $error("Invalid SHIFT=%0d. SHIFT must be >= 0.", SHIFT);
            $fatal;
        end

        for (c = 0; c < NTAPS; c = c + 1) begin
            coef_array[c] = {CW{1'b0}};
        end

        $readmemh(COEF_FILE, coef_array);
    end


    // MAC (convinational) + registered output
    // Note: For high Fmax, pipeline the adder tree or use DSP cascade.
    reg signed [ACCW-1:0] acc;
    reg signed [ACCW-1:0] acc_shifted;
    reg signed [ACCW-1:0] round_bias;
    
    reg signed [ACCW:0] acc_ext;    // Extended acc.
    reg signed [ACCW:0] bias_ext;   // Extended bias.
    reg signed [ACCW:0] mag_ext;    // Extended mag.
    reg signed [ACCW:0] scaled_ext; // Extended scaled.
    
    integer j;
    always @(*) begin
        // Clear all vectors
        acc         = {ACCW{1'b0}};
        acc_shifted = {ACCW{1'b0}};
        round_bias  = {ACCW{1'b0}};
        
        acc_ext     = {(ACCW+1){1'b0}};
        bias_ext    = {(ACCW+1){1'b0}};
        mag_ext     = {(ACCW+1){1'b0}};
        scaled_ext  = {(ACCW+1){1'b0}};  
        
        // MAC computation
        for(j = 0; j < NTAPS; j=j+1) begin
            acc = acc + (xz[j] * coef_array[j]); // (XW+CW) product; acc must be wide enough
        end
        
        // Fixed-point scaling: 
        // assume coeff is Q1.15 => shift by 15 to return to input scale.
        // Rounding mode implemented here is "round to nearest", also called "ties away from zero".
        
//        if ((ROUND_TO_NEAREST != 0) && (SHIFT > 0)) begin
//            round_bias = {{(ACCW-1){1'b0}}, 1'b1};
//            round_bias = round_bias <<< (SHIFT - 1);
//            if (acc >= 0)
//                acc_shifted = (acc + round_bias) >>> SHIFT;
//            else
//                acc_shifted = (acc - round_bias) >>> SHIFT;
//        end else if (SHIFT > 0) begin
//            acc_shifted = acc >>> SHIFT;
//        end else begin
//            acc_shifted = acc;
//        end

        if ((ROUND_TO_NEAREST != 0) && (SHIFT > 0)) begin
            acc_ext  = {acc[ACCW-1], acc}; // keeps the sign of acc and hold the acc value
        
            bias_ext = {{ACCW{1'b0}}, 1'b1};  // Numeric value = 1 with width (ACCW+1)
            bias_ext = bias_ext <<< (SHIFT - 1);
            round_bias = bias_ext[ACCW-1:0];
        
            if (acc_ext < 0) begin
                mag_ext     = -acc_ext;
                scaled_ext  = (mag_ext + bias_ext) >>> SHIFT;
                acc_shifted = -scaled_ext[ACCW-1:0];
            end else begin
                scaled_ext  = (acc_ext + bias_ext) >>> SHIFT;
                acc_shifted = scaled_ext[ACCW-1:0];
            end
        end else if (SHIFT > 0) begin
            acc_shifted = acc >>> SHIFT;
        end else begin
            acc_shifted = acc;
        end 
    end 

    // Saturation helper
    /*
    By default, functions use static memory allocation, meaning local variables retain their
    values between calls. Using the automatic keyword makes the function re-entrant, allocating 
    dynamic memory for each call, which is necessary for recursive functions. 
    */
    function automatic signed [YW-1:0] sat_y;
        input signed [ACCW-1:0] v;
        reg signed [YW-1:0] maxv, minv;
    begin
        maxv = {1'b0, {(YW-1){1'b1}}}; // 32767
        minv = {1'b1, {(YW-1){1'b0}}}; // -32768
        if (v > maxv)      sat_y = maxv;
        else if (v < minv) sat_y = minv;
        else               sat_y = v[YW-1:0];
    end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            y_out   <= {YW{1'b0}};
            y_valid <= 1'b0;
        end else begin
            // y_valid aligns to when an output is updated (en asserted)
            y_valid <= en;
            if (en) begin
                y_out <= sat_y(acc_shifted);
            end
        end
    end
endmodule
