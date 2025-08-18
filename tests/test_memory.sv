`timescale 1ns/1ps

module test_memory;

  localparam int WORDS = 1024; // 64 words of memory
  localparam int DATA_WIDTH = 32;
  localparam real CLK_PERIOD = 10.0; // 100 MHz clock
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;
  reg test_failed;

  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish; // End simulation
    end
  endtask

  // dut io
  reg clk;
  reg rst_n;
  reg [DATA_WIDTH-1:0] addr;
  reg [DATA_WIDTH-1:0] data_in;
  reg mem_write;
  wire [DATA_WIDTH-1:0] data_out;

  // dut instantiation
  memory #(
    .WORDS(WORDS),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .data_in(data_in),
    .mem_write(mem_write),
    .data_out(data_out)
  );

  // clock
  initial begin
    clk = 0;
    forever begin
      #(CLK_HALF_PERIOD) clk = !clk;
    end
  end

  task write_word(input [DATA_WIDTH-1:0] wad, input [DATA_WIDTH-1:0] wdt);
    begin
      @(negedge clk);
      addr = wad;
      data_in = wdt;
      mem_write = 1;
      @(negedge clk); // wait for write to complete
      mem_write = 0;
      data_in = '0;
    end
  endtask

  task read_word(input [DATA_WIDTH-1:0] rad, input [DATA_WIDTH-1:0] rexp);
    begin
      @(negedge clk);
      addr = rad;
      #1; // wait for data_out to be updated
      if (data_out !== rexp) begin
        test_failed = 1;
        $display("[%0t] error: addr=0x%0h expected=0x%08x, got=0x%08x", $time, addr, rexp, data_out);
      end else begin
        $display("[%0t] OK: addr=0x%0h data=0x%08x", $time, addr, data_out);
      end
    end
  endtask

  initial begin
    $dumpfile("./tests/results/test_memory.vcd");
    $dumpvars(0, test_memory);

    addr = '0;
    data_in = '0;
    mem_write = 0;

    rst_n = 0; // pull reset low
    repeat (2) @(posedge clk); // @ second posedge clk
    rst_n = 1; // release reset
    @(posedge clk);

    // read uninitialized memory
    read_word(32'h00000010, 32'h0);
    read_word(32'h00000000, 32'h0);
    read_word(32'h00000008, 32'h0);

    repeat (2) @(posedge clk); // rest for two clock cycles (20ns)

    repeat (100) begin
      reg [DATA_WIDTH-1:0] rs;
      reg [DATA_WIDTH-1:0] rd;

      rs = {$random} & ~(8-1) & 32'h000000FF; // random & bit_not(7) = random & !...111 = random000 = byte-aligned address; then set the first 24 bits to zero to keep within the 256 bytes of memory
      rd = {$random};
      write_word(rs, rd); // write random data to random address
      read_word(rs, rd); // read back the value
    end

    repeat (2) @(posedge clk); // wait for clock edges to capture the last event.
    finish;
  end

endmodule
