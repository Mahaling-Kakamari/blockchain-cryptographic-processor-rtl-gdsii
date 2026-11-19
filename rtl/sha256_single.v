`timescale 1ns/1ps

module sha256_single (
    input wire clk,
    input wire rst_n,
    
    // Control Interface
    input wire start,           // 1 = Start processing block
    input wire mode_init,       // 1 = First block (load standard IVs), 0 = Next block (use internal state)
    output reg ready,           // 1 = Idle, ready for input
    output reg done,            // 1 = Valid hash output (pulsed)
    
    // Data Interface
    input wire [511:0] block_in,
    output wire [255:0] digest_out
);

    // -------------------------------------------------------------------------
    // Parameters & Defines
    // -------------------------------------------------------------------------
    
    // Initial Hash Values (H0) - Fractional parts of square roots of first 8 primes
    localparam H0_0 = 32'h6a09e667;
    localparam H0_1 = 32'hbb67ae85;
    localparam H0_2 = 32'h3c6ef372;
    localparam H0_3 = 32'ha54ff53a;
    localparam H0_4 = 32'h510e527f;
    localparam H0_5 = 32'h9b05688c;
    localparam H0_6 = 32'h1f83d9ab;
    localparam H0_7 = 32'h5be0cd19;

    // FSM States
    localparam S_IDLE   = 2'd0;
    localparam S_LOAD   = 2'd1; // Cycle to load scheduler and init core
    localparam S_WORK   = 2'd2; // 64 rounds of compression
    localparam S_FINAL  = 2'd3; // Add compressed state to accumulated hash
    
    reg [1:0] state, next_state;
    reg [5:0] round_ctr;

    // -------------------------------------------------------------------------
    // Internal Registers & Signals
    // -------------------------------------------------------------------------
    
    // Message Scheduler Signals
    reg [31:0] w_mem [0:15]; // 16-word sliding window
    wire [31:0] w_t;         // Current word W_t
    wire [31:0] next_w_calc;
    
    // Round Constant
    reg [31:0] k_t;
    
    // Core Compression State
    reg [31:0] a, b, c, d, e, f, g, h;
    wire [31:0] a_next, b_next, c_next, d_next, e_next, f_next, g_next, h_next;
    wire [31:0] T1, T2;

    // Accumulator Registers (The H values transmitted between blocks)
    reg [31:0] H0, H1, H2, H3, H4, H5, H6, H7;
    
    integer i;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------
    
    function [31:0] rotr;
        input [31:0] x;
        input [5:0]  n;
        begin
            rotr = (x >> n) | (x << (32-n));
        end
    endfunction
    
    function [31:0] shr;
        input [31:0] x;
        input [5:0]  n;
        begin
            shr = x >> n;
        end
    endfunction

    function [31:0] ch;
        input [31:0] x, y, z;
        begin
            ch = (x & y) ^ (~x & z);
        end
    endfunction

    function [31:0] maj;
        input [31:0] x, y, z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    function [31:0] big_sigma0;
        input [31:0] x;
        begin
            big_sigma0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
        end
    endfunction

    function [31:0] big_sigma1;
        input [31:0] x;
        begin
            big_sigma1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
        end
    endfunction

    function [31:0] small_sigma0;
        input [31:0] x;
        begin
            small_sigma0 = rotr(x, 7) ^ rotr(x, 18) ^ shr(x, 3);
        end
    endfunction

    function [31:0] small_sigma1;
        input [31:0] x;
        begin
            small_sigma1 = rotr(x, 17) ^ rotr(x, 19) ^ shr(x, 10);
        end
    endfunction

    // -------------------------------------------------------------------------
    // 1. K Constant Lookup
    // -------------------------------------------------------------------------
    always @(*) begin
        case (round_ctr)
            6'd0 : k_t = 32'h428a2f98; 6'd1 : k_t = 32'h71374491; 6'd2 : k_t = 32'hb5c0fbcf; 6'd3 : k_t = 32'he9b5dba5;
            6'd4 : k_t = 32'h3956c25b; 6'd5 : k_t = 32'h59f111f1; 6'd6 : k_t = 32'h923f82a4; 6'd7 : k_t = 32'hab1c5ed5;
            6'd8 : k_t = 32'hd807aa98; 6'd9 : k_t = 32'h12835b01; 6'd10: k_t = 32'h243185be; 6'd11: k_t = 32'h550c7dc3;
            6'd12: k_t = 32'h72be5d74; 6'd13: k_t = 32'h80deb1fe; 6'd14: k_t = 32'h9bdc06a7; 6'd15: k_t = 32'hc19bf174;
            6'd16: k_t = 32'he49b69c1; 6'd17: k_t = 32'hefbe4786; 6'd18: k_t = 32'h0fc19dc6; 6'd19: k_t = 32'h240ca1cc;
            6'd20: k_t = 32'h2de92c6f; 6'd21: k_t = 32'h4a7484aa; 6'd22: k_t = 32'h5cb0a9dc; 6'd23: k_t = 32'h76f988da;
            6'd24: k_t = 32'h983e5152; 6'd25: k_t = 32'ha831c66d; 6'd26: k_t = 32'hb00327c8; 6'd27: k_t = 32'hbf597fc7;
            6'd28: k_t = 32'hc6e00bf3; 6'd29: k_t = 32'hd5a79147; 6'd30: k_t = 32'h06ca6351; 6'd31: k_t = 32'h14292967;
            6'd32: k_t = 32'h27b70a85; 6'd33: k_t = 32'h2e1b2138; 6'd34: k_t = 32'h4d2c6dfc; 6'd35: k_t = 32'h53380d13;
            6'd36: k_t = 32'h650a7354; 6'd37: k_t = 32'h766a0abb; 6'd38: k_t = 32'h81c2c92e; 6'd39: k_t = 32'h92722c85;
            6'd40: k_t = 32'ha2bfe8a1; 6'd41: k_t = 32'ha81a664b; 6'd42: k_t = 32'hc24b8b70; 6'd43: k_t = 32'hc76c51a3;
            6'd44: k_t = 32'hd192e819; 6'd45: k_t = 32'hd6990624; 6'd46: k_t = 32'hf40e3585; 6'd47: k_t = 32'h106aa070;
            6'd48: k_t = 32'h19a4c116; 6'd49: k_t = 32'h1e376c08; 6'd50: k_t = 32'h2748774c; 6'd51: k_t = 32'h34b0bcb5;
            6'd52: k_t = 32'h391c0cb3; 6'd53: k_t = 32'h4ed8aa4a; 6'd54: k_t = 32'h5b9cca4f; 6'd55: k_t = 32'h682e6ff3;
            6'd56: k_t = 32'h748f82ee; 6'd57: k_t = 32'h78a5636f; 6'd58: k_t = 32'h84c87814; 6'd59: k_t = 32'h8cc70208;
            6'd60: k_t = 32'h90befffa; 6'd61: k_t = 32'ha4506ceb; 6'd62: k_t = 32'hbef9a3f7; 6'd63: k_t = 32'hc67178f2;
            default: k_t = 32'h0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 2. Message Scheduler Logic
    // -------------------------------------------------------------------------
    // W_t for current round is w_mem[0]
    assign w_t = w_mem[0];
    
    // Calculation for next W (pushed in at w_mem[15])
    assign next_w_calc = small_sigma1(w_mem[14]) + w_mem[9] + small_sigma0(w_mem[1]) + w_mem[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<16; i=i+1) w_mem[i] <= 32'd0;
        end else if (state == S_LOAD) begin
            // Load block: w_in[511:480] -> w_mem[0], etc.
            w_mem[0]  <= block_in[511:480];
            w_mem[1]  <= block_in[479:448];
            w_mem[2]  <= block_in[447:416];
            w_mem[3]  <= block_in[415:384];
            w_mem[4]  <= block_in[383:352];
            w_mem[5]  <= block_in[351:320];
            w_mem[6]  <= block_in[319:288];
            w_mem[7]  <= block_in[287:256];
            w_mem[8]  <= block_in[255:224];
            w_mem[9]  <= block_in[223:192];
            w_mem[10] <= block_in[191:160];
            w_mem[11] <= block_in[159:128];
            w_mem[12] <= block_in[127:96];
            w_mem[13] <= block_in[95:64];
            w_mem[14] <= block_in[63:32];
            w_mem[15] <= block_in[31:0];
        end else if (state == S_WORK) begin
            // Shift and load new calculated value
            for (i=0; i<15; i=i+1) begin
                w_mem[i] <= w_mem[i+1];
            end
            w_mem[15] <= next_w_calc;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Core Combination Logic
    // -------------------------------------------------------------------------
    
    assign T1 = h + big_sigma1(e) + ch(e, f, g) + k_t + w_t;
    assign T2 = big_sigma0(a) + maj(a, b, c);
    
    assign a_next = T1 + T2;
    assign b_next = a;
    assign c_next = b;
    assign d_next = c;
    assign e_next = d + T1;
    assign f_next = e;
    assign g_next = f;
    assign h_next = g;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0;
            e <= 32'd0; f <= 32'd0; g <= 32'd0; h <= 32'd0;
        end else if (state == S_LOAD) begin
            // Initialize with current Hash state
            a <= H0; b <= H1; c <= H2; d <= H3;
            e <= H4; f <= H5; g <= H6; h <= H7;
        end else if (state == S_WORK) begin
            // Update registers with next state
            a <= a_next;
            b <= b_next;
            c <= c_next;
            d <= d_next;
            e <= e_next;
            f <= f_next;
            g <= g_next;
            h <= h_next;
        end
    end

    // -------------------------------------------------------------------------
    // 4. FSM Logic
    // -------------------------------------------------------------------------
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else state <= next_state;
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start) next_state = S_LOAD;
            end
            S_LOAD: begin
                next_state = S_WORK;
            end
            S_WORK: begin
                if (round_ctr == 6'd63) next_state = S_FINAL;
            end
            S_FINAL: begin
                next_state = S_IDLE;
            end
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) round_ctr <= 6'd0;
        else if (state == S_LOAD) round_ctr <= 6'd0;
        else if (state == S_WORK) round_ctr <= round_ctr + 1;
    end
    
    always @(*) begin
        ready = (state == S_IDLE);
        done = (state == S_FINAL);
    end

    // -------------------------------------------------------------------------
    // 5. Hash Accumulation (Linker)
    // -------------------------------------------------------------------------
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            H0 <= H0_0; H1 <= H0_1; H2 <= H0_2; H3 <= H0_3;
            H4 <= H0_4; H5 <= H0_5; H6 <= H0_6; H7 <= H0_7;
        end else if (state == S_LOAD && mode_init) begin
            // Reset to standard IVs for first block of message
            H0 <= H0_0; H1 <= H0_1; H2 <= H0_2; H3 <= H0_3;
            H4 <= H0_4; H5 <= H0_5; H6 <= H0_6; H7 <= H0_7;
        end else if (state == S_FINAL) begin
            // Add compressed chunk to current hash state
            H0 <= H0 + a;
            H1 <= H1 + b;
            H2 <= H2 + c;
            H3 <= H3 + d;
            H4 <= H4 + e;
            H5 <= H5 + f;
            H6 <= H6 + g;
            H7 <= H7 + h;
        end
    end
    
    assign digest_out = {H0, H1, H2, H3, H4, H5, H6, H7};

    // DEBUGGING
    // always @(posedge clk) begin
    //     if (state == S_WORK) begin
    //         $display("Cycle %t | Round %d | W=%h | K=%h | a=%h e=%h", $time, round_ctr, w_t, k_t, a, e);
    //     end
    //     if (state == S_FINAL) begin
    //          $display("FINAL STATE | a=%h b=%h ... | H0_old=%h", a, b, H0);
    //     end
    // end

endmodule
