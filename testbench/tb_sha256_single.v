`timescale 1ns/1ps

module tb_sha256_single;

    reg clk;
    reg rst_n;
    reg start;
    reg mode_init;
    reg [511:0] block_in;
    
    wire ready;
    wire done;
    wire [255:0] digest_out;
    
    // Instantiation of the single flattened module
    sha256_single dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode_init(mode_init),
        .ready(ready),
        .done(done),
        .block_in(block_in),
        .digest_out(digest_out)
    );
    
    // Clock Generation
    always #5 clk = ~clk; // 100MHz clock
    
    initial begin
        // Enable Waveform Dump
        $dumpfile("dump_single.vcd");
        $dumpvars(0, tb_sha256_single);

        // Initialize
        clk = 0;
        rst_n = 0;
        start = 0;
        mode_init = 0;
        block_in = 0;
        
        // Reset
        #20 rst_n = 1;
        
        // Test Case 1: "abc"
        // Expected Hash: ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
        
        // Wait for ready
        wait(ready);
        
        // Setup Input Padded Block for "abc"
        // "abc" = 0x616263
        // Append '1' bit -> 0x61626380
        // Padding zeros...
        // Last 64 bits = length in bits = 24 = 0x18
        
        block_in[511:480] = 32'h61626380; // Word 0
        block_in[479:448] = 32'h0;        // Word 1
        block_in[447:416] = 32'h0;
        block_in[415:384] = 32'h0;
        block_in[383:352] = 32'h0;
        block_in[351:320] = 32'h0;
        block_in[319:288] = 32'h0;
        block_in[287:256] = 32'h0;
        block_in[255:224] = 32'h0;
        block_in[223:192] = 32'h0;
        block_in[191:160] = 32'h0;
        block_in[159:128] = 32'h0;
        block_in[127:96]  = 32'h0;        // Word 13
        block_in[95:64]   = 32'h0;        // Word 14
        block_in[63:0]    = 64'h18;       // Word 15 (Length 24)
        
        // Start Transaction
        @(posedge clk);
        mode_init = 1; // First block
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for Done
        wait(done);
        repeat(200) @(posedge clk);
        
        // Check Result
        $display("----------------------------------------------------------------");
        $display("SHA-256 (Single Module) Simulation Results");
        $display("----------------------------------------------------------------");
        $display("Input: 'abc'");
        $display("Expected: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        $display("Got:      %h", digest_out);
        
        if (digest_out == 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad)
            $display("STATUS: PASS");
        else
            $display("STATUS: FAIL");
            
        $display("----------------------------------------------------------------");
        
        $finish;
    end

endmodule
