//=====================================================================
// Flat Single-Module SHA-256 Hardware Accelerator (Verilog-2001)
// - No submodules
// - Synchronous reset
// - Registered inputs/outputs
// - One round per cycle (64 cycles after start)
// - SHA-256 for ONE 512-bit message block (block must be pre-padded)
//=====================================================================

`timescale 1ns/1ps

module blockchain (
    input  wire         clk,
    input  wire         rst,      // synchronous reset
    input  wire         start,    // pulse to start hashing 'block_in'
    input  wire [511:0] block_in, // 512-bit message block (already padded)
    output reg          done,     // 1-cycle pulse when digest valid
    output reg  [255:0] digest_out
);

    //=============================================================
    // K constants (SHA-256)
    //=============================================================
    localparam [31:0] K0  = 32'h428a2f98;
    localparam [31:0] K1  = 32'h71374491;
    localparam [31:0] K2  = 32'hb5c0fbcf;
    localparam [31:0] K3  = 32'he9b5dba5;
    localparam [31:0] K4  = 32'h3956c25b;
    localparam [31:0] K5  = 32'h59f111f1;
    localparam [31:0] K6  = 32'h923f82a4;
    localparam [31:0] K7  = 32'hab1c5ed5;
    localparam [31:0] K8  = 32'hd807aa98;
    localparam [31:0] K9  = 32'h12835b01;
    localparam [31:0] K10 = 32'h243185be;
    localparam [31:0] K11 = 32'h550c7dc3;
    localparam [31:0] K12 = 32'h72be5d74;
    localparam [31:0] K13 = 32'h80deb1fe;
    localparam [31:0] K14 = 32'h9bdc06a7;
    localparam [31:0] K15 = 32'hc19bf174;
    localparam [31:0] K16 = 32'he49b69c1;
    localparam [31:0] K17 = 32'hefbe4786;
    localparam [31:0] K18 = 32'h0fc19dc6;
    localparam [31:0] K19 = 32'h240ca1cc;
    localparam [31:0] K20 = 32'h2de92c6f;
    localparam [31:0] K21 = 32'h4a7484aa;
    localparam [31:0] K22 = 32'h5cb0a9dc;
    localparam [31:0] K23 = 32'h76f988da;
    localparam [31:0] K24 = 32'h983e5152;
    localparam [31:0] K25 = 32'ha831c66d;
    localparam [31:0] K26 = 32'hb00327c8;
    localparam [31:0] K27 = 32'hbf597fc7;
    localparam [31:0] K28 = 32'hc6e00bf3;
    localparam [31:0] K29 = 32'hd5a79147;
    localparam [31:0] K30 = 32'h06ca6351;
    localparam [31:0] K31 = 32'h14292967;
    localparam [31:0] K32 = 32'h27b70a85;
    localparam [31:0] K33 = 32'h2e1b2138;
    localparam [31:0] K34 = 32'h4d2c6dfc;
    localparam [31:0] K35 = 32'h53380d13;
    localparam [31:0] K36 = 32'h650a7354;
    localparam [31:0] K37 = 32'h766a0abb;
    localparam [31:0] K38 = 32'h81c2c92e;
    localparam [31:0] K39 = 32'h92722c85;
    localparam [31:0] K40 = 32'ha2bfe8a1;
    localparam [31:0] K41 = 32'ha81a664b;
    localparam [31:0] K42 = 32'hc24b8b70;
    localparam [31:0] K43 = 32'hc76c51a3;
    localparam [31:0] K44 = 32'hd192e819;
    localparam [31:0] K45 = 32'hd6990624;
    localparam [31:0] K46 = 32'hf40e3585;
    localparam [31:0] K47 = 32'h106aa070;
    localparam [31:0] K48 = 32'h19a4c116;
    localparam [31:0] K49 = 32'h1e376c08;
    localparam [31:0] K50 = 32'h2748774c;
    localparam [31:0] K51 = 32'h34b0bcb5;
    localparam [31:0] K52 = 32'h391c0cb3;
    localparam [31:0] K53 = 32'h4ed8aa4a;
    localparam [31:0] K54 = 32'h5b9cca4f;
    localparam [31:0] K55 = 32'h682e6ff3;
    localparam [31:0] K56 = 32'h748f82ee;
    localparam [31:0] K57 = 32'h78a5636f;
    localparam [31:0] K58 = 32'h84c87814;
    localparam [31:0] K59 = 32'h8cc70208;
    localparam [31:0] K60 = 32'h90befffa;
    localparam [31:0] K61 = 32'ha4506ceb;
    localparam [31:0] K62 = 32'hbef9a3f7;
    localparam [31:0] K63 = 32'hc67178f2;

    //=============================================================
    // FSM states
    //=============================================================
    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_LOAD  = 2'd1;
    localparam [1:0] S_ROUND = 2'd2;
    localparam [1:0] S_DONE  = 2'd3;

    reg [1:0] state;

    //=============================================================
    // Registered inputs
    //=============================================================
    reg [511:0] block_r;

    //=============================================================
    // Message schedule shift register: last 16 W's
    // Wbuf[0] oldest ... Wbuf[15] newest
    //=============================================================
    reg [31:0] Wbuf0, Wbuf1, Wbuf2, Wbuf3, Wbuf4, Wbuf5, Wbuf6, Wbuf7;
    reg [31:0] Wbuf8, Wbuf9, Wbuf10, Wbuf11, Wbuf12, Wbuf13, Wbuf14, Wbuf15;

    //=============================================================
    // Hash IV / accumulators
    //=============================================================
    reg [31:0] H0, H1, H2, H3, H4, H5, H6, H7;

    // Working registers
    reg [31:0] a,b,c,d,e,f,g,h;

    // Round counter
    reg [5:0] t;

    //=============================================================
    // Utility functions
    //=============================================================
    function [31:0] rotr32;
        input [31:0] x;
        input [4:0]  n;
        begin
            rotr32 = (x >> n) | (x << (32 - n));
        end
    endfunction

    function [31:0] shr32;
        input [31:0] x;
        input [4:0]  n;
        begin
            shr32 = (x >> n);
        end
    endfunction

    function [31:0] Ch;
        input [31:0] x,y,z;
        begin
            Ch = (x & y) ^ ((~x) & z);
        end
    endfunction

    function [31:0] Maj;
        input [31:0] x,y,z;
        begin
            Maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    function [31:0] SIG0;
        input [31:0] x;
        begin
            SIG0 = rotr32(x,2) ^ rotr32(x,13) ^ rotr32(x,22);
        end
    endfunction

    function [31:0] SIG1;
        input [31:0] x;
        begin
            SIG1 = rotr32(x,6) ^ rotr32(x,11) ^ rotr32(x,25);
        end
    endfunction

    function [31:0] sig0;
        input [31:0] x;
        begin
            sig0 = rotr32(x,7) ^ rotr32(x,18) ^ shr32(x,3);
        end
    endfunction

    function [31:0] sig1;
        input [31:0] x;
        begin
            sig1 = rotr32(x,17) ^ rotr32(x,19) ^ shr32(x,10);
        end
    endfunction

    //=============================================================
    // K mux (combinational)
    //=============================================================
    reg [31:0] Kt;
    always @(*) begin
        case (t)
            6'd0:  Kt = K0;
            6'd1:  Kt = K1;
            6'd2:  Kt = K2;
            6'd3:  Kt = K3;
            6'd4:  Kt = K4;
            6'd5:  Kt = K5;
            6'd6:  Kt = K6;
            6'd7:  Kt = K7;
            6'd8:  Kt = K8;
            6'd9:  Kt = K9;
            6'd10: Kt = K10;
            6'd11: Kt = K11;
            6'd12: Kt = K12;
            6'd13: Kt = K13;
            6'd14: Kt = K14;
            6'd15: Kt = K15;
            6'd16: Kt = K16;
            6'd17: Kt = K17;
            6'd18: Kt = K18;
            6'd19: Kt = K19;
            6'd20: Kt = K20;
            6'd21: Kt = K21;
            6'd22: Kt = K22;
            6'd23: Kt = K23;
            6'd24: Kt = K24;
            6'd25: Kt = K25;
            6'd26: Kt = K26;
            6'd27: Kt = K27;
            6'd28: Kt = K28;
            6'd29: Kt = K29;
            6'd30: Kt = K30;
            6'd31: Kt = K31;
            6'd32: Kt = K32;
            6'd33: Kt = K33;
            6'd34: Kt = K34;
            6'd35: Kt = K35;
            6'd36: Kt = K36;
            6'd37: Kt = K37;
            6'd38: Kt = K38;
            6'd39: Kt = K39;
            6'd40: Kt = K40;
            6'd41: Kt = K41;
            6'd42: Kt = K42;
            6'd43: Kt = K43;
            6'd44: Kt = K44;
            6'd45: Kt = K45;
            6'd46: Kt = K46;
            6'd47: Kt = K47;
            6'd48: Kt = K48;
            6'd49: Kt = K49;
            6'd50: Kt = K50;
            6'd51: Kt = K51;
            6'd52: Kt = K52;
            6'd53: Kt = K53;
            6'd54: Kt = K54;
            6'd55: Kt = K55;
            6'd56: Kt = K56;
            6'd57: Kt = K57;
            6'd58: Kt = K58;
            6'd59: Kt = K59;
            6'd60: Kt = K60;
            6'd61: Kt = K61;
            6'd62: Kt = K62;
            6'd63: Kt = K63;
            default: Kt = 32'h00000000;
        endcase
    end

    //=============================================================
    // Current Wt and computed Wnew
    //=============================================================
    reg [31:0] Wt;
    reg [31:0] Wnew;

    always @(*) begin
        // Default assignments (avoid latch)
        Wt   = 32'h0;
        Wnew = 32'h0;

        // Current Wt always comes from Wbuf[t] for 0..15 else Wbuf15 newest
        if (t < 6'd16) begin
            case (t)
                6'd0:  Wt = Wbuf0;
                6'd1:  Wt = Wbuf1;
                6'd2:  Wt = Wbuf2;
                6'd3:  Wt = Wbuf3;
                6'd4:  Wt = Wbuf4;
                6'd5:  Wt = Wbuf5;
                6'd6:  Wt = Wbuf6;
                6'd7:  Wt = Wbuf7;
                6'd8:  Wt = Wbuf8;
                6'd9:  Wt = Wbuf9;
                6'd10: Wt = Wbuf10;
                6'd11: Wt = Wbuf11;
                6'd12: Wt = Wbuf12;
                6'd13: Wt = Wbuf13;
                6'd14: Wt = Wbuf14;
                6'd15: Wt = Wbuf15;
                default: Wt = 32'h0;
            endcase
        end else begin
            Wt = Wbuf15;
        end

        // Wnew = sig1(W[t-2]) + W[t-7] + sig0(W[t-15]) + W[t-16]
        // Using shift-buffer mapping:
        //   W[t-16] = Wbuf0
        //   W[t-15] = Wbuf1
        //   W[t-7]  = Wbuf9
        //   W[t-2]  = Wbuf14
        Wnew = sig1(Wbuf14) + Wbuf9 + sig0(Wbuf1) + Wbuf0;
    end

    //=============================================================
    // Round combinational values
    //=============================================================
    reg [31:0] T1, T2;
    always @(*) begin
        T1 = h + SIG1(e) + Ch(e,f,g) + Kt + Wt;
        T2 = SIG0(a) + Maj(a,b,c);
    end

    //=============================================================
    // Main sequential logic
    //=============================================================
    always @(posedge clk) begin
        if (rst) begin
            // control
            state      <= S_IDLE;
            done       <= 1'b0;
            t          <= 6'd0;

            // registered IO
            block_r    <= 512'h0;
            digest_out <= 256'h0;

            // W schedule regs
            Wbuf0  <= 32'h0; Wbuf1  <= 32'h0; Wbuf2  <= 32'h0; Wbuf3  <= 32'h0;
            Wbuf4  <= 32'h0; Wbuf5  <= 32'h0; Wbuf6  <= 32'h0; Wbuf7  <= 32'h0;
            Wbuf8  <= 32'h0; Wbuf9  <= 32'h0; Wbuf10 <= 32'h0; Wbuf11 <= 32'h0;
            Wbuf12 <= 32'h0; Wbuf13 <= 32'h0; Wbuf14 <= 32'h0; Wbuf15 <= 32'h0;

            // hash state
            H0 <= 32'h6a09e667; H1 <= 32'hbb67ae85; H2 <= 32'h3c6ef372; H3 <= 32'ha54ff53a;
            H4 <= 32'h510e527f; H5 <= 32'h9b05688c; H6 <= 32'h1f83d9ab; H7 <= 32'h5be0cd19;

            // working vars
            a <= 32'h0; b <= 32'h0; c <= 32'h0; d <= 32'h0;
            e <= 32'h0; f <= 32'h0; g <= 32'h0; h <= 32'h0;

        end else begin
            // defaults
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    t <= 6'd0;
                    if (start) begin
                        // Register input block
                        block_r <= block_in;
                        state   <= S_LOAD;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                S_LOAD: begin
                    // Load W0..W15 from block_r (big-endian 32-bit words)
                    Wbuf0  <= block_r[511:480];
                    Wbuf1  <= block_r[479:448];
                    Wbuf2  <= block_r[447:416];
                    Wbuf3  <= block_r[415:384];
                    Wbuf4  <= block_r[383:352];
                    Wbuf5  <= block_r[351:320];
                    Wbuf6  <= block_r[319:288];
                    Wbuf7  <= block_r[287:256];
                    Wbuf8  <= block_r[255:224];
                    Wbuf9  <= block_r[223:192];
                    Wbuf10 <= block_r[191:160];
                    Wbuf11 <= block_r[159:128];
                    Wbuf12 <= block_r[127:96];
                    Wbuf13 <= block_r[95:64];
                    Wbuf14 <= block_r[63:32];
                    Wbuf15 <= block_r[31:0];

                    // Initialize IV
                    H0 <= 32'h6a09e667; H1 <= 32'hbb67ae85; H2 <= 32'h3c6ef372; H3 <= 32'ha54ff53a;
                    H4 <= 32'h510e527f; H5 <= 32'h9b05688c; H6 <= 32'h1f83d9ab; H7 <= 32'h5be0cd19;

                    // Load working vars
                    a <= 32'h6a09e667;
                    b <= 32'hbb67ae85;
                    c <= 32'h3c6ef372;
                    d <= 32'ha54ff53a;
                    e <= 32'h510e527f;
                    f <= 32'h9b05688c;
                    g <= 32'h1f83d9ab;
                    h <= 32'h5be0cd19;

                    t     <= 6'd0;
                    state <= S_ROUND;
                end

                S_ROUND: begin
                    // Perform one round
                    h <= g;
                    g <= f;
                    f <= e;
                    e <= d + T1;
                    d <= c;
                    c <= b;
                    b <= a;
                    a <= T1 + T2;

                    // Update W schedule shift register AFTER using Wt in this cycle.
                    if (t >= 6'd16) begin
                        Wbuf0  <= Wbuf1;
                        Wbuf1  <= Wbuf2;
                        Wbuf2  <= Wbuf3;
                        Wbuf3  <= Wbuf4;
                        Wbuf4  <= Wbuf5;
                        Wbuf5  <= Wbuf6;
                        Wbuf6  <= Wbuf7;
                        Wbuf7  <= Wbuf8;
                        Wbuf8  <= Wbuf9;
                        Wbuf9  <= Wbuf10;
                        Wbuf10 <= Wbuf11;
                        Wbuf11 <= Wbuf12;
                        Wbuf12 <= Wbuf13;
                        Wbuf13 <= Wbuf14;
                        Wbuf14 <= Wbuf15;
                        Wbuf15 <= Wnew;
                    end else begin
                        // keep values stable for first 16 rounds
                        Wbuf0  <= Wbuf0;  Wbuf1  <= Wbuf1;  Wbuf2  <= Wbuf2;  Wbuf3  <= Wbuf3;
                        Wbuf4  <= Wbuf4;  Wbuf5  <= Wbuf5;  Wbuf6  <= Wbuf6;  Wbuf7  <= Wbuf7;
                        Wbuf8  <= Wbuf8;  Wbuf9  <= Wbuf9;  Wbuf10 <= Wbuf10; Wbuf11 <= Wbuf11;
                        Wbuf12 <= Wbuf12; Wbuf13 <= Wbuf13; Wbuf14 <= Wbuf14; Wbuf15 <= Wbuf15;
                    end

                    // Advance / finalize
                    if (t == 6'd63) begin
                        // Final digest add (H + working)
                        H0 <= H0 + (T1 + T2);
                        H1 <= H1 + a;
                        H2 <= H2 + b;
                        H3 <= H3 + c;
                        H4 <= H4 + (d + T1);
                        H5 <= H5 + e;
                        H6 <= H6 + f;
                        H7 <= H7 + g;

                        digest_out <= {
                            (H0 + (T1 + T2)),
                            (H1 + a),
                            (H2 + b),
                            (H3 + c),
                            (H4 + (d + T1)),
                            (H5 + e),
                            (H6 + f),
                            (H7 + g)
                        };

                        done  <= 1'b1;
                        t     <= 6'd0;
                        state <= S_DONE;
                    end else begin
                        t     <= t + 6'd1;
                        state <= S_ROUND;
                    end
                end

                S_DONE: begin
                    // Hold digest stable, return to IDLE
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

