`timescale 1ns/1ps

// runs a program that prints over the uart and checks the characters on the serial line.
// run from soc/k0 through ./programs/run.sh, which builds the image.
module test_hello;

  parameter IMAGE = "";
  parameter EXPECTED = "hello, lucknow\n";
  parameter int LENGTH = 15; // characters in EXPECTED
  parameter int CLKS_PER_BIT = 8;
  parameter MAX_CYCLES = 100000;

  localparam real CLK_HALF_PERIOD = 5.0;

  reg clk;
  reg rst_n;
  wire uart_tx;

  soc #(
    .RAM_INIT(IMAGE),
    .UART_CLKS_PER_BIT(CLKS_PER_BIT)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_tx(uart_tx)
  );

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  initial begin
    rst_n = 0;
    #2;
    rst_n = 1;
  end

  // serial receiver
  reg [7:0] received [0:255];
  integer count;
  integer bit_index;
  initial begin
    count = 0;
    forever begin
      @(negedge uart_tx);
      repeat (CLKS_PER_BIT + CLKS_PER_BIT / 2) @(posedge clk);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        received[count][bit_index] = uart_tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end
      count = count + 1;
    end
  end

  integer cycles;
  integer ok;
  initial begin
    cycles = 0;
    while (count < LENGTH && cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    ok = (count == LENGTH);
    for (int c = 0; c < LENGTH && c < count; c = c + 1) begin
      if (received[c] !== EXPECTED[(LENGTH - 1 - c) * 8 +: 8]) ok = 0;
    end
    if (ok) begin
      $display("PASS: %0d characters in %0d cycles", count, cycles);
    end else begin
      $display("FAIL: expected %0d characters, got %0d", LENGTH, count);
      for (int c = 0; c < count; c = c + 1) $display("  [%0d] 0x%02x", c, received[c]);
    end
    $finish;
  end

endmodule
