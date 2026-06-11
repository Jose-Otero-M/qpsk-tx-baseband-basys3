`timescale 1ns/1ps

module tb_2;

    // Define TB_CHECK_INTERNALS only for RTL simulation when hierarchical
    // references into the DUT are available and stable.
    
    //`define TB_CHECK_INTERNALS
    
    localparam int CLK_PERIOD_NS          = 10;
    localparam int CLK_FREQ_HZ            = 100_000_000; //32;
    localparam int BIT_RATE_HZ            = 100_000;//8;
    localparam int OSR_ACC_W              = 32;//32;//8;
    localparam int RRC_FILTER_SPS         = 4;
    localparam int RRC_N_TAPS             = 33;
    localparam int RRC_INPUT_W            = 16;
    localparam int RRC_COEF_W             = 16;
    localparam int RRC_OUT_W              = 16;
    localparam int RRC_ACC_W              = 40;
    localparam int RRC_SHIFT              = 15;
    localparam int RRC_ROUND_TO_NEAREST   = 0;
    localparam int MAPPER_OUT_W           = 16;
    localparam int MAPPER_AMP             = 16'd23170;
    localparam int SYM_RATE_HZ            = BIT_RATE_HZ / 2;
    localparam int RRC_SAMPLE_RATE_HZ     = SYM_RATE_HZ * RRC_FILTER_SPS;
    localparam int BIT_PERIOD_CLKS        = CLK_FREQ_HZ / BIT_RATE_HZ;          /////////////////////////////////////// 2777.7777
    localparam int SAMPLE_PERIOD_CLKS     = CLK_FREQ_HZ / RRC_SAMPLE_RATE_HZ;   /////////////////////////////////////// 1388.8888
    //localparam int NUM_SYMBOLS            = 12;
    localparam int FLUSH_SAMPLE_COUNT     = RRC_N_TAPS + (2 * RRC_FILTER_SPS); // Ends simulation using an extra time.

    logic clk;
    logic rst;
    logic bit_in;
    logic bit_valid;

    wire signed [RRC_OUT_W-1:0] rrc_i;
    wire signed [RRC_OUT_W-1:0] rrc_q;
    wire                        valid_rrc_out_i;
    wire                        valid_rrc_out_q;

    //logic [1:0] symbol_stream [0:NUM_SYMBOLS-1];
    logic signed [RRC_COEF_W-1:0] taps [0:RRC_N_TAPS-1];

    logic [1:0] sym_bits_exp;
    logic       sym_valid_exp;
    logic       have_1bit_exp;
    logic       b0_exp;

    logic signed [MAPPER_OUT_W-1:0] I_sym_exp;
    logic signed [MAPPER_OUT_W-1:0] Q_sym_exp;
    logic                           iq_valid_exp;

    logic                           sample_en_exp;
    integer                         sample_div_cnt_exp;

    logic signed [MAPPER_OUT_W-1:0] I_zero_exp;
    logic signed [MAPPER_OUT_W-1:0] Q_zero_exp;
    logic                           zero_valid_exp;
    integer                         zeros_remaining_exp;
    logic signed [MAPPER_OUT_W-1:0] symbol_queue_i[$];
    logic signed [MAPPER_OUT_W-1:0] symbol_queue_q[$];

    logic signed [RRC_INPUT_W-1:0] hist_i [0:RRC_N_TAPS-2];
    logic signed [RRC_INPUT_W-1:0] hist_q [0:RRC_N_TAPS-2];
    logic signed [RRC_OUT_W-1:0]   y_i_exp;
    logic signed [RRC_OUT_W-1:0]   y_q_exp;
    logic                          y_valid_exp;

    integer cycle_count;
    integer err_count;
    integer sym_count_seen;
    integer mapper_count_seen;
    integer sample_count_seen;
    integer rrc_count_seen;
    integer rrc_dump_fd;
    
    localparam int N_BITS = 65536;
    localparam NUM_SYMBOLS = N_BITS / 2;
    integer bitstream_fd;
    logic bit_mem [0:N_BITS-1];
    integer file_bitstream_fd;



    top_QPSK_baseband_tx #(
        .MAPPER_OUT_W(MAPPER_OUT_W),
        .MAPPER_AMP(MAPPER_AMP),
        .OSR_ACC_W(OSR_ACC_W),
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BIT_RATE_HZ(BIT_RATE_HZ),
        .RRC_FILTER_SPS(RRC_FILTER_SPS),
        .RRC_N_TAPS(RRC_N_TAPS),
        .RRC_INPUT_W(RRC_INPUT_W),
        .RRC_COEF_W(RRC_COEF_W),
        .RRC_OUT_W(RRC_OUT_W),
        .RRC_ACC_W(RRC_ACC_W),
        .RRC_SHIFT(RRC_SHIFT),
        .RRC_ROUND_TO_NEAREST(RRC_ROUND_TO_NEAREST)
    ) dut (
        .clk(clk),
        .rst(rst),
        .bit_in(bit_in),
        .bit_valid(bit_valid),
        .rrc_i(rrc_i),
        .rrc_q(rrc_q),
        .valid_rrc_out_i(valid_rrc_out_i),
        .valid_rrc_out_q(valid_rrc_out_q)
    );

    function automatic logic signed [MAPPER_OUT_W-1:0] mapper_i_ref(input logic [1:0] bits);
        case (bits)
            2'b00: mapper_i_ref = -MAPPER_AMP;
            2'b01: mapper_i_ref = -MAPPER_AMP;
            2'b11: mapper_i_ref =  MAPPER_AMP;
            2'b10: mapper_i_ref =  MAPPER_AMP;
            default: mapper_i_ref = '0;
        endcase
    endfunction

    function automatic logic signed [MAPPER_OUT_W-1:0] mapper_q_ref(input logic [1:0] bits);
        case (bits)
            2'b00: mapper_q_ref = -MAPPER_AMP;
            2'b01: mapper_q_ref =  MAPPER_AMP;
            2'b11: mapper_q_ref =  MAPPER_AMP;
            2'b10: mapper_q_ref = -MAPPER_AMP;
            default: mapper_q_ref = '0;
        endcase
    endfunction

    function automatic longint signed round_shift_ref(input longint signed value);
        longint signed bias;
        begin
            if (RRC_SHIFT > 0) begin
                if (RRC_ROUND_TO_NEAREST != 0) begin
                    bias = 1;
                    bias = bias <<< (RRC_SHIFT - 1);
                    if (value >= 0)
                        round_shift_ref = (value + bias) >>> RRC_SHIFT;
                    else
                        round_shift_ref = (value - bias) >>> RRC_SHIFT;
                end else begin
                    round_shift_ref = value >>> RRC_SHIFT;
                end
            end else begin
                round_shift_ref = value;
            end
        end
    endfunction

    function automatic logic signed [RRC_OUT_W-1:0] sat_ref(input longint signed value);
        longint signed maxv;
        longint signed minv;
        begin
            maxv = (1 <<< (RRC_OUT_W-1)) - 1;
            minv = -(1 <<< (RRC_OUT_W-1));
            if (value > maxv)
                sat_ref = maxv[RRC_OUT_W-1:0];
            else if (value < minv)
                sat_ref = minv[RRC_OUT_W-1:0];
            else
                sat_ref = value[RRC_OUT_W-1:0];
        end
    endfunction

    task automatic check_signal(
        input bit condition,
        input string tag
    );
        begin
            if (!condition) begin
                err_count = err_count + 1;
                $display("[%0t] ERROR: %s", $time, tag);
            end
        end
    endtask

    task automatic send_bit(input logic bit_value);
        begin
            @(negedge clk);
            bit_in    <= bit_value;
            bit_valid <= 1'b1;

            @(negedge clk);
            bit_valid <= 1'b0;

            repeat (BIT_PERIOD_CLKS-1) @(negedge clk);
        end
    endtask

    task automatic send_symbol(input logic [1:0] symbol_bits);
        begin
            send_bit(symbol_bits[1]);
            send_bit(symbol_bits[0]);
        end
    endtask

    integer idx;
    integer tap_idx;
    integer hist_idx;
    longint signed acc_i_model;
    longint signed acc_q_model;
    integer scan_status;
    int bit_value;
    
    
    initial begin
        if ((BIT_RATE_HZ % 2) != 0) begin
            $fatal(1, "BIT_RATE_HZ must be even for QPSK.");
        end

        if ((CLK_FREQ_HZ % BIT_RATE_HZ) != 0) begin
            $fatal(1, "This testbench expects an integer bit period in clocks.");
        end

        if ((CLK_FREQ_HZ % RRC_SAMPLE_RATE_HZ) != 0) begin
            $fatal(1, "This testbench expects an integer sample period in clocks.");
        end

//        symbol_stream[0]  = 2'b00;
//        symbol_stream[1]  = 2'b01;
//        symbol_stream[2]  = 2'b11;
//        symbol_stream[3]  = 2'b10;
//        symbol_stream[4]  = 2'b00;
//        symbol_stream[5]  = 2'b10;
//        symbol_stream[6]  = 2'b11;
//        symbol_stream[7]  = 2'b01;
//        symbol_stream[8]  = 2'b01;
//        symbol_stream[9]  = 2'b00;
//        symbol_stream[10] = 2'b10;
//        symbol_stream[11] = 2'b11;


        file_bitstream_fd = $fopen("prbs_65536_bits.txt", "r");
        
        if (file_bitstream_fd == 0) begin
            $fatal(1, "Error: Could not open PRBS input file.");
        end
        
        for (idx = 0; idx < N_BITS; idx++) begin
            scan_status = $fscanf(file_bitstream_fd, "%d\n", bit_value);
    
            if (scan_status != 1) begin
                $fatal(1, "Error: Could not read bit %0d from PRBS input file.", idx);
            end
    
            bit_mem[idx] = bit_value[0];
        end
        
        //$fclose(file_bitstream_fd);

        $display("PRBS input file loaded successfully. Total bits: %0d", N_BITS);
        
        
        
        $readmemh("rrc_taps_q15_energy.mem", taps);

        clk                 = 1'b0;
        rst                 = 1'b1;
        bit_in              = 1'b0;
        bit_valid           = 1'b0;
        cycle_count         = 0;
        err_count           = 0;
        sym_count_seen      = 0;
        mapper_count_seen   = 0;
        sample_count_seen   = 0;
        rrc_count_seen      = 0;
        rrc_dump_fd         = $fopen("tb_top_QPSK_baseband_tx_rrc_samples.csv", "w");

        if (rrc_dump_fd == 0) begin
            $fatal(1, "Could not open tb_top_QPSK_baseband_tx_rrc_samples.csv");
        end
        // Header
        $fwrite(rrc_dump_fd, "sample_index, time, rrc_i, rrc_q\n");
        $fflush(rrc_dump_fd);
        
        repeat (4) @(negedge clk);
        rst <= 1'b0;

//        repeat (2) @(negedge clk);
//        for (idx = 0; idx < NUM_SYMBOLS; idx = idx + 1) begin
//            send_symbol(symbol_stream[idx]);
//        end

        repeat (2) @(negedge clk);
        for (idx = 0; idx < NUM_SYMBOLS; idx = idx + 1) begin
            send_symbol({bit_mem[2*idx], bit_mem[2*idx+1]});
        end


        repeat ((FLUSH_SAMPLE_COUNT * SAMPLE_PERIOD_CLKS) + (2 * BIT_PERIOD_CLKS)) @(negedge clk);

        $display("------------------------------------------------------------");
        $display("Simulation summary");
        $display("  Symbols checked      : %0d", sym_count_seen);
        $display("  Mapper events checked: %0d", mapper_count_seen);
        $display("  Sample events checked: %0d", sample_count_seen);
        $display("  RRC outputs checked  : %0d", rrc_count_seen);
        $display("  Errors               : %0d", err_count);
        $display("------------------------------------------------------------");

        $fclose(rrc_dump_fd);
        $fclose(file_bitstream_fd);
        
        if (err_count == 0) begin
            $display("TB PASSED");
        end else begin
            $fatal(1, "TB FAILED with %0d errors.", err_count);
        end
        
        
        $finish;
    end

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            sample_div_cnt_exp <= 0;
            sample_en_exp      <= 1'b0;
        end else begin
            if (sample_div_cnt_exp == (SAMPLE_PERIOD_CLKS - 1)) begin
                sample_div_cnt_exp <= 0;
                sample_en_exp      <= 1'b1;
            end else begin
                sample_div_cnt_exp <= sample_div_cnt_exp + 1;
                sample_en_exp      <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            have_1bit_exp <= 1'b0;
            b0_exp        <= 1'b0;
            sym_bits_exp  <= 2'b00;
            sym_valid_exp <= 1'b0;
        end else begin
            sym_valid_exp <= 1'b0;
            if (bit_valid) begin
                if (!have_1bit_exp) begin
                    b0_exp        <= bit_in;
                    have_1bit_exp <= 1'b1;
                end else begin
                    sym_bits_exp  <= {b0_exp, bit_in};
                    sym_valid_exp <= 1'b1;
                    have_1bit_exp <= 1'b0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            I_sym_exp   <= '0;
            Q_sym_exp   <= '0;
            iq_valid_exp <= 1'b0;
        end else begin
            iq_valid_exp <= 1'b0;
            if (sym_valid_exp) begin
                I_sym_exp   <= mapper_i_ref(sym_bits_exp);
                Q_sym_exp   <= mapper_q_ref(sym_bits_exp);
                iq_valid_exp <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            symbol_queue_i.delete();
            symbol_queue_q.delete();
            I_zero_exp           <= '0;
            Q_zero_exp           <= '0;
            zero_valid_exp       <= 1'b0;
            zeros_remaining_exp  <= 0;
        end else begin
            if (iq_valid_exp) begin
                symbol_queue_i.push_back(I_sym_exp);
                symbol_queue_q.push_back(Q_sym_exp);
            end

            zero_valid_exp <= 1'b0;

            if (sample_en_exp) begin
                zero_valid_exp <= 1'b1;
                if (zeros_remaining_exp > 0) begin
                    I_zero_exp          <= '0;
                    Q_zero_exp          <= '0;
                    zeros_remaining_exp = zeros_remaining_exp - 1;
                end else if (symbol_queue_i.size() > 0) begin
                    I_zero_exp          <= symbol_queue_i[0];
                    Q_zero_exp          <= symbol_queue_q[0];
                    symbol_queue_i.pop_front();
                    symbol_queue_q.pop_front();
                    zeros_remaining_exp = RRC_FILTER_SPS - 1;
                end else begin
                    I_zero_exp <= '0;
                    Q_zero_exp <= '0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            y_i_exp    <= '0;
            y_q_exp    <= '0;
            y_valid_exp <= 1'b0;
            for (hist_idx = 0; hist_idx < (RRC_N_TAPS - 1); hist_idx = hist_idx + 1) begin
                hist_i[hist_idx] = '0;
                hist_q[hist_idx] = '0;
            end
        end else begin
            y_valid_exp <= zero_valid_exp;

            if (zero_valid_exp) begin
                acc_i_model = $signed(I_zero_exp) * $signed(taps[0]);
                acc_q_model = $signed(Q_zero_exp) * $signed(taps[0]);

                for (tap_idx = 1; tap_idx < RRC_N_TAPS; tap_idx = tap_idx + 1) begin
                    acc_i_model = acc_i_model + ($signed(hist_i[tap_idx-1]) * $signed(taps[tap_idx]));
                    acc_q_model = acc_q_model + ($signed(hist_q[tap_idx-1]) * $signed(taps[tap_idx]));
                end

                y_i_exp <= sat_ref(round_shift_ref(acc_i_model));
                y_q_exp <= sat_ref(round_shift_ref(acc_q_model));

                for (hist_idx = RRC_N_TAPS-2; hist_idx > 0; hist_idx = hist_idx - 1) begin
                    hist_i[hist_idx] = hist_i[hist_idx-1];
                    hist_q[hist_idx] = hist_q[hist_idx-1];
                end

                hist_i[0] = I_zero_exp;
                hist_q[0] = Q_zero_exp;
            end
        end
    end

    always @(negedge clk) begin
        if (!rst) begin
`ifdef TB_CHECK_INTERNALS
            check_signal(dut.stb_sample_at_Rs_SPS === sample_en_exp,
                $sformatf("sample_en mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, dut.stb_sample_at_Rs_SPS, sample_en_exp));

            check_signal(dut.sym_valid_stb === sym_valid_exp,
                $sformatf("sym_valid mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, dut.sym_valid_stb, sym_valid_exp));

            check_signal(dut.sym_bits === sym_bits_exp,
                $sformatf("sym_bits mismatch at cycle %0d. dut=%b exp=%b",
                    cycle_count, dut.sym_bits, sym_bits_exp));

            check_signal(dut.iq_valid_stb === iq_valid_exp,
                $sformatf("iq_valid mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, dut.iq_valid_stb, iq_valid_exp));

            check_signal(dut.I_sym === I_sym_exp,
                $sformatf("I_sym mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, dut.I_sym, I_sym_exp));

            check_signal(dut.Q_sym === Q_sym_exp,
                $sformatf("Q_sym mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, dut.Q_sym, Q_sym_exp));

            check_signal(dut.valid_iq_resampled === zero_valid_exp,
                $sformatf("zero stuffer valid mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, dut.valid_iq_resampled, zero_valid_exp));

            check_signal(dut.I_resampled === I_zero_exp,
                $sformatf("I_resampled mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, dut.I_resampled, I_zero_exp));

            check_signal(dut.Q_resampled === Q_zero_exp,
                $sformatf("Q_resampled mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, dut.Q_resampled, Q_zero_exp));
`endif

            check_signal(valid_rrc_out_i === y_valid_exp,
                $sformatf("valid_rrc_out_i mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, valid_rrc_out_i, y_valid_exp));

            check_signal(valid_rrc_out_q === y_valid_exp,
                $sformatf("valid_rrc_out_q mismatch at cycle %0d. dut=%0b exp=%0b",
                    cycle_count, valid_rrc_out_q, y_valid_exp));

            check_signal(rrc_i === y_i_exp,
                $sformatf("rrc_i mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, rrc_i, y_i_exp));

            check_signal(rrc_q === y_q_exp,
                $sformatf("rrc_q mismatch at cycle %0d. dut=%0d exp=%0d",
                    cycle_count, rrc_q, y_q_exp));

            if (sym_valid_exp) begin
                sym_count_seen = sym_count_seen + 1;
            end

            if (iq_valid_exp) begin
                mapper_count_seen = mapper_count_seen + 1;
            end

            if (zero_valid_exp) begin
                sample_count_seen = sample_count_seen + 1;
            end

            if (y_valid_exp) begin
                rrc_count_seen = rrc_count_seen + 1;
                $fwrite(rrc_dump_fd, "%0d, %0t, %0d, %0d\n", rrc_count_seen-1, $time, $signed(rrc_i), $signed(rrc_q));
                $fflush(rrc_dump_fd);
            end
        end
    end

endmodule
