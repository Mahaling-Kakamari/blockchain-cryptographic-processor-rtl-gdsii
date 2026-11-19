//==============================================================================
// File: sha256_final.v
// Description: Optimized SHA-256 Single Block Processor
//              Synthesis-friendly RTL for Cadence Genus/Innovus flow
// Features: 
//   - Clean FSM with proper state encoding
//   - Separated K-constant ROM
//   - Optimized for timing closure
//   - Reduced combinational depth
//==============================================================================

`timescale 1ns/1ps

module sha256_final (
    input wire clk,
    input wire rst_n,
    
    // Control Interface
    input wire start,           // Start processing block
    input wire mode_init,       // 1=First block (load IVs), 0=Continue with current hash
    output wire ready,          // Ready for new input
    output wire done,           // Valid hash output (pulsed)
    
    // Data Interface
    input wire [511:0] block_in,
    output wire [255:0] digest_out
);

    //==========================================================================
    // Parameters & Constants
    //==========================================================================
    
    // Initial Hash Values (H0) - SHA-256 standard IVs
    localparam [31:0] H0_0 = 32'h6a09e667;
    localparam [31:0] H0_1 = 32'hbb67ae85;
    localparam [31:0] H0_2 = 32'h3c6ef372;
    localparam [31:0] H0_3 = 32'ha54ff53a;
    localparam [31:0] H0_4 = 32'h510e527f;
    localparam [31:0] H0_5 = 32'h9b05688c;
    localparam [31:0] H0_6 = 32'h1f83d9ab;
    localparam [31:0] H0_7 = 32'h5be0cd19;

    // FSM States - One-hot encoding for better synthesis
    localparam [3:0] S_IDLE   = 4'b0001;
    localparam [3:0] S_LOAD   = 4'b0010;
    localparam [3:0] S_WORK   = 4'b0100;
    localparam [3:0] S_FINAL  = 4'b1000;

    //==========================================================================
    // Internal Registers & Wires
    //==========================================================================
    
    // FSM Control
    reg [3:0] state_reg, state_next;
    reg [5:0] round_ctr_reg, round_ctr_next;
    reg ready_reg, done_reg;
    
    // Message Schedule Window (W array)
    reg [31:0] w_mem_reg [0:15];
    reg [31:0] w_mem_next [0:15];
    wire [31:0] w_t;
    wire [31:0] next_w_calc;
    
    // Round Constant from ROM
    wire [31:0] k_t;
    
    // Working Variables (a-h)
    reg [31:0] a_reg, b_reg, c_reg, d_reg;
    reg [31:0] e_reg, f_reg, g_reg, h_reg;
    reg [31:0] a_next, b_next, c_next, d_next;
    reg [31:0] e_next, f_next, g_next, h_next;
    
    // Intermediate calculation registers for timing
    wire [31:0] T1, T2;
    wire [31:0] ch_result, maj_result;
    wire [31:0] big_sigma0_result, big_sigma1_result;
    
    // Hash Accumulator Registers
    reg [31:0] H0_reg, H1_reg, H2_reg, H3_reg;
    reg [31:0] H4_reg, H5_reg, H6_reg, H7_reg;
    reg [31:0] H0_next, H1_next, H2_next, H3_next;
    reg [31:0] H4_next, H5_next, H6_next, H7_next;
    
    // Loop index
    integer idx;

    //==========================================================================
    // SHA-256 Functions (Combinational Logic)
    //==========================================================================
    
    // Rotate Right
    function automatic [31:0] rotr;
        input [31:0] x;
        input [5:0]  n;
        begin
            rotr = (x >> n) | (x << (32 - n));
        end
    endfunction
    
    // Shift Right
    function automatic [31:0] shr;
        input [31:0] x;
        input [5:0]  n;
        begin
            shr = x >> n;
        end
    endfunction

    // Ch(x,y,z) = (x AND y) XOR (NOT x AND z)
    function automatic [31:0] ch;
        input [31:0] x, y, z;
        begin
            ch = (x & y) ^ (~x & z);
        end
    endfunction

    // Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z)
    function automatic [31:0] maj;
        input [31:0] x, y, z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    // Σ0(x) = ROTR^2(x) XOR ROTR^13(x) XOR ROTR^22(x)
    function automatic [31:0] big_sigma0;
        input [31:0] x;
        begin
            big_sigma0 = rotr(x, 6'd2) ^ rotr(x, 6'd13) ^ rotr(x, 6'd22);
        end
    endfunction

    // Σ1(x) = ROTR^6(x) XOR ROTR^11(x) XOR ROTR^25(x)
    function automatic [31:0] big_sigma1;
        input [31:0] x;
        begin
            big_sigma1 = rotr(x, 6'd6) ^ rotr(x, 6'd11) ^ rotr(x, 6'd25);
        end
    endfunction

    // σ0(x) = ROTR^7(x) XOR ROTR^18(x) XOR SHR^3(x)
    function automatic [31:0] small_sigma0;
        input [31:0] x;
        begin
            small_sigma0 = rotr(x, 6'd7) ^ rotr(x, 6'd18) ^ shr(x, 6'd3);
        end
    endfunction

    // σ1(x) = ROTR^17(x) XOR ROTR^19(x) XOR SHR^10(x)
    function automatic [31:0] small_sigma1;
        input [31:0] x;
        begin
            small_sigma1 = rotr(x, 6'd17) ^ rotr(x, 6'd19) ^ shr(x, 6'd10);
        end
    endfunction

    //==========================================================================
    // K Constants ROM (64 constants for 64 rounds)
    //==========================================================================
    
    sha256_k_rom u_k_rom (
        .round_addr(round_ctr_reg),
        .k_value(k_t)
    );

    //==========================================================================
    // Message Scheduler Logic
    //==========================================================================
    
    // Current W value for this round
    assign w_t = w_mem_reg[0];
    
    // Calculate next W value: W[t] = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]
    assign next_w_calc = small_sigma1(w_mem_reg[14]) + 
                         w_mem_reg[9] + 
                         small_sigma0(w_mem_reg[1]) + 
                         w_mem_reg[0];
    
    // Message schedule array update logic
    always @(*) begin
        for (idx = 0; idx < 16; idx = idx + 1) begin
            w_mem_next[idx] = w_mem_reg[idx];
        end
        
        case (state_reg)
            S_LOAD: begin
                // Load input block (big-endian)
                w_mem_next[0]  = block_in[511:480];
                w_mem_next[1]  = block_in[479:448];
                w_mem_next[2]  = block_in[447:416];
                w_mem_next[3]  = block_in[415:384];
                w_mem_next[4]  = block_in[383:352];
                w_mem_next[5]  = block_in[351:320];
                w_mem_next[6]  = block_in[319:288];
                w_mem_next[7]  = block_in[287:256];
                w_mem_next[8]  = block_in[255:224];
                w_mem_next[9]  = block_in[223:192];
                w_mem_next[10] = block_in[191:160];
                w_mem_next[11] = block_in[159:128];
                w_mem_next[12] = block_in[127:96];
                w_mem_next[13] = block_in[95:64];
                w_mem_next[14] = block_in[63:32];
                w_mem_next[15] = block_in[31:0];
            end
            
            S_WORK: begin
                // Shift window and load new calculated value
                for (idx = 0; idx < 15; idx = idx + 1) begin
                    w_mem_next[idx] = w_mem_reg[idx + 1];
                end
                w_mem_next[15] = next_w_calc;
            end
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                w_mem_reg[idx] <= 32'h0;
            end
        end else begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                w_mem_reg[idx] <= w_mem_next[idx];
            end
        end
    end

    //==========================================================================
    // Core Compression Function
    //==========================================================================
    
    // Calculate intermediate values
    assign ch_result = ch(e_reg, f_reg, g_reg);
    assign maj_result = maj(a_reg, b_reg, c_reg);
    assign big_sigma0_result = big_sigma0(a_reg);
    assign big_sigma1_result = big_sigma1(e_reg);
    
    // T1 = h + Σ1(e) + Ch(e,f,g) + Kt + Wt
    assign T1 = h_reg + big_sigma1_result + ch_result + k_t + w_t;
    
    // T2 = Σ0(a) + Maj(a,b,c)
    assign T2 = big_sigma0_result + maj_result;
    
    // Working variables update logic
    always @(*) begin
        case (state_reg)
            S_LOAD: begin
                // Initialize with current hash state
                a_next = H0_reg;
                b_next = H1_reg;
                c_next = H2_reg;
                d_next = H3_reg;
                e_next = H4_reg;
                f_next = H5_reg;
                g_next = H6_reg;
                h_next = H7_reg;
            end
            
            S_WORK: begin
                // Compression function
                a_next = T1 + T2;
                b_next = a_reg;
                c_next = b_reg;
                d_next = c_reg;
                e_next = d_reg + T1;
                f_next = e_reg;
                g_next = f_reg;
                h_next = g_reg;
            end
            
            default: begin
                a_next = a_reg;
                b_next = b_reg;
                c_next = c_reg;
                d_next = d_reg;
                e_next = e_reg;
                f_next = f_reg;
                g_next = g_reg;
                h_next = h_reg;
            end
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= 32'h0;
            b_reg <= 32'h0;
            c_reg <= 32'h0;
            d_reg <= 32'h0;
            e_reg <= 32'h0;
            f_reg <= 32'h0;
            g_reg <= 32'h0;
            h_reg <= 32'h0;
        end else begin
            a_reg <= a_next;
            b_reg <= b_next;
            c_reg <= c_next;
            d_reg <= d_next;
            e_reg <= e_next;
            f_reg <= f_next;
            g_reg <= g_next;
            h_reg <= h_next;
        end
    end

    //==========================================================================
    // FSM State Machine
    //==========================================================================
    
    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= S_IDLE;
        end else begin
            state_reg <= state_next;
        end
    end
    
    // Next state logic
    always @(*) begin
        state_next = state_reg;
        
        case (state_reg)
            S_IDLE: begin
                if (start) begin
                    state_next = S_LOAD;
                end
            end
            
            S_LOAD: begin
                state_next = S_WORK;
            end
            
            S_WORK: begin
                if (round_ctr_reg == 6'd63) begin
                    state_next = S_FINAL;
                end
            end
            
            S_FINAL: begin
                state_next = S_IDLE;
            end
            
            default: begin
                state_next = S_IDLE;
            end
        endcase
    end
    
    // Round counter
    always @(*) begin
        if (state_reg == S_LOAD) begin
            round_ctr_next = 6'd0;
        end else if (state_reg == S_WORK) begin
            round_ctr_next = round_ctr_reg + 6'd1;
        end else begin
            round_ctr_next = round_ctr_reg;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_ctr_reg <= 6'd0;
        end else begin
            round_ctr_reg <= round_ctr_next;
        end
    end
    
    // Output control signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_reg <= 1'b1;
            done_reg <= 1'b0;
        end else begin
            ready_reg <= (state_reg == S_IDLE);
            done_reg <= (state_reg == S_FINAL);
        end
    end
    
    assign ready = ready_reg;
    assign done = done_reg;

    //==========================================================================
    // Hash Accumulation (H registers)
    //==========================================================================
    
    always @(*) begin
        if ((state_reg == S_LOAD) && mode_init) begin
            // Initialize with standard IVs
            H0_next = H0_0;
            H1_next = H0_1;
            H2_next = H0_2;
            H3_next = H0_3;
            H4_next = H0_4;
            H5_next = H0_5;
            H6_next = H0_6;
            H7_next = H0_7;
        end else if (state_reg == S_FINAL) begin
            // Add compressed state to hash accumulator
            H0_next = H0_reg + a_reg;
            H1_next = H1_reg + b_reg;
            H2_next = H2_reg + c_reg;
            H3_next = H3_reg + d_reg;
            H4_next = H4_reg + e_reg;
            H5_next = H5_reg + f_reg;
            H6_next = H6_reg + g_reg;
            H7_next = H7_reg + h_reg;
        end else begin
            H0_next = H0_reg;
            H1_next = H1_reg;
            H2_next = H2_reg;
            H3_next = H3_reg;
            H4_next = H4_reg;
            H5_next = H5_reg;
            H6_next = H6_reg;
            H7_next = H7_reg;
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            H0_reg <= H0_0;
            H1_reg <= H0_1;
            H2_reg <= H0_2;
            H3_reg <= H0_3;
            H4_reg <= H0_4;
            H5_reg <= H0_5;
            H6_reg <= H0_6;
            H7_reg <= H0_7;
        end else begin
            H0_reg <= H0_next;
            H1_reg <= H1_next;
            H2_reg <= H2_next;
            H3_reg <= H3_next;
            H4_reg <= H4_next;
            H5_reg <= H5_next;
            H6_reg <= H6_next;
            H7_reg <= H7_next;
        end
    end
    
    // Output hash digest
    assign digest_out = {H0_reg, H1_reg, H2_reg, H3_reg, H4_reg, H5_reg, H6_reg, H7_reg};

endmodule


//==============================================================================
// K Constants ROM Module
// Contains 64 round constants for SHA-256
//==============================================================================

module sha256_k_rom (
    input wire [5:0] round_addr,
    output reg [31:0] k_value
);

    // K constant lookup table
    always @(*) begin
        case (round_addr)
            6'd0 : k_value = 32'h428a2f98;
            6'd1 : k_value = 32'h71374491;
            6'd2 : k_value = 32'hb5c0fbcf;
            6'd3 : k_value = 32'he9b5dba5;
            6'd4 : k_value = 32'h3956c25b;
            6'd5 : k_value = 32'h59f111f1;
            6'd6 : k_value = 32'h923f82a4;
            6'd7 : k_value = 32'hab1c5ed5;
            6'd8 : k_value = 32'hd807aa98;
            6'd9 : k_value = 32'h12835b01;
            6'd10: k_value = 32'h243185be;
            6'd11: k_value = 32'h550c7dc3;
            6'd12: k_value = 32'h72be5d74;
            6'd13: k_value = 32'h80deb1fe;
            6'd14: k_value = 32'h9bdc06a7;
            6'd15: k_value = 32'hc19bf174;
            6'd16: k_value = 32'he49b69c1;
            6'd17: k_value = 32'hefbe4786;
            6'd18: k_value = 32'h0fc19dc6;
            6'd19: k_value = 32'h240ca1cc;
            6'd20: k_value = 32'h2de92c6f;
            6'd21: k_value = 32'h4a7484aa;
            6'd22: k_value = 32'h5cb0a9dc;
            6'd23: k_value = 32'h76f988da;
            6'd24: k_value = 32'h983e5152;
            6'd25: k_value = 32'ha831c66d;
            6'd26: k_value = 32'hb00327c8;
            6'd27: k_value = 32'hbf597fc7;
            6'd28: k_value = 32'hc6e00bf3;
            6'd29: k_value = 32'hd5a79147;
            6'd30: k_value = 32'h06ca6351;
            6'd31: k_value = 32'h14292967;
            6'd32: k_value = 32'h27b70a85;
            6'd33: k_value = 32'h2e1b2138;
            6'd34: k_value = 32'h4d2c6dfc;
            6'd35: k_value = 32'h53380d13;
            6'd36: k_value = 32'h650a7354;
            6'd37: k_value = 32'h766a0abb;
            6'd38: k_value = 32'h81c2c92e;
            6'd39: k_value = 32'h92722c85;
            6'd40: k_value = 32'ha2bfe8a1;
            6'd41: k_value = 32'ha81a664b;
            6'd42: k_value = 32'hc24b8b70;
            6'd43: k_value = 32'hc76c51a3;
            6'd44: k_value = 32'hd192e819;
            6'd45: k_value = 32'hd6990624;
            6'd46: k_value = 32'hf40e3585;
            6'd47: k_value = 32'h106aa070;
            6'd48: k_value = 32'h19a4c116;
            6'd49: k_value = 32'h1e376c08;
            6'd50: k_value = 32'h2748774c;
            6'd51: k_value = 32'h34b0bcb5;
            6'd52: k_value = 32'h391c0cb3;
            6'd53: k_value = 32'h4ed8aa4a;
            6'd54: k_value = 32'h5b9cca4f;
            6'd55: k_value = 32'h682e6ff3;
            6'd56: k_value = 32'h748f82ee;
            6'd57: k_value = 32'h78a5636f;
            6'd58: k_value = 32'h84c87814;
            6'd59: k_value = 32'h8cc70208;
            6'd60: k_value = 32'h90befffa;
            6'd61: k_value = 32'ha4506ceb;
            6'd62: k_value = 32'hbef9a3f7;
            6'd63: k_value = 32'hc67178f2;
            default: k_value = 32'h0;
        endcase
    end

endmodule
