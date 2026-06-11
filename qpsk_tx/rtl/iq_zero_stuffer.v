module iq_zero_stuffer #(
    parameter integer DATA_W = 16,
    parameter integer SPS    = 4
)(
    input  wire                           clk,
    input  wire                           rst,

    input  wire                           sample_en,     // One-clock strobe at output sample rate: Fs = Rs * SPS
    input  wire                           in_valid_stb,  // One-clock strobe at symbol rate: Rs

    input  wire signed [DATA_W-1:0]       I_sym_in,
    input  wire signed [DATA_W-1:0]       Q_sym_in,

    output reg  signed [DATA_W-1:0]       I_out,
    output reg  signed [DATA_W-1:0]       Q_out,
    output reg                            out_valid_stb
);

    localparam integer ZERO_W = (SPS <= 1) ? 1 : $clog2(SPS);

    reg [ZERO_W-1:0] zero_count;

    reg signed [DATA_W-1:0] I_pending;
    reg signed [DATA_W-1:0] Q_pending;
    reg                     pending_valid;

    always @(posedge clk) begin
        if (rst) begin
            zero_count    <= {ZERO_W{1'b0}};
            I_pending     <= {DATA_W{1'b0}};
            Q_pending     <= {DATA_W{1'b0}};
            pending_valid <= 1'b0;

            I_out         <= {DATA_W{1'b0}};
            Q_out         <= {DATA_W{1'b0}};
            out_valid_stb <= 1'b0;
        end else begin
            out_valid_stb <= 1'b0;

            // Emit one output sample only when sample_en is asserted.
            if (sample_en) begin
                out_valid_stb <= 1'b1;

                if (zero_count != {ZERO_W{1'b0}}) begin     // zero_count != 0?
                    // Remaining samples of the symbol period: explicit zero stuffing.
                    I_out      <= {DATA_W{1'b0}};
                    Q_out      <= {DATA_W{1'b0}};
                    zero_count <= zero_count - 1'b1;

                    if (in_valid_stb && !pending_valid) begin
                        I_pending     <= I_sym_in;
                        Q_pending     <= Q_sym_in;
                        pending_valid <= 1'b1;
                    end
                end else if (pending_valid) begin
                    // Start of a new symbol period. Emit the queued symbol first.
                    I_out      <= I_pending;
                    Q_out      <= Q_pending;
                    zero_count <= (SPS - 1);

                    if (in_valid_stb) begin
                        // Queue the next symbol if it arrives exactly when the current one is emitted.
                        I_pending     <= I_sym_in;
                        Q_pending     <= Q_sym_in;
                        pending_valid <= 1'b1;
                    end else begin
                        pending_valid <= 1'b0;
                    end
                end else if (in_valid_stb) begin
                    // Symbol and sample strobes coincide: emit directly.
                    I_out         <= I_sym_in;
                    Q_out         <= Q_sym_in;
                    zero_count    <= (SPS - 1);
                    pending_valid <= 1'b0;
                end else begin
                    // No symbol available yet: keep emitting zeros until one arrives.
                    I_out <= {DATA_W{1'b0}};
                    Q_out <= {DATA_W{1'b0}};
                end
            end else if (in_valid_stb) begin
                // Queue a symbol between sample strobes.
                if (!pending_valid) begin
                    I_pending     <= I_sym_in;
                    Q_pending     <= Q_sym_in;
                    pending_valid <= 1'b1;
                end

// Simulation-only guard: a new symbol arrived while the one-entry pending buffer
// is still occupied. This indicates the input symbol rate is not being serviced
// correctly by the sample strobe, or that deeper buffering is required.                
`ifndef SYNTHESIS
                else begin
                    $error("iq_zero_stuffer pending buffer overflow. Check the Rs/Fs relationship or add buffering.");
                end
`endif
            end
        end
    end

    initial begin
        if (SPS < 1) begin
            $error("Invalid SPS value. SPS must be >= 1.");
            $fatal;
        end
    end

endmodule
