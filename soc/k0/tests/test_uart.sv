`timescale 1ns/1ps

module test_uart;

  localparam int CLKS_PER_BIT = 4;
  localparam real CLK_HALF_PERIOD = 5.0;

  reg test_failed;
  task finish;
    begin
      if (test_failed) begin
        $display("Test failed!");
      end else begin
        $display("Test passed!");
      end
      $finish;
    end
  endtask

  reg clk;
  reg rst_n;
  reg sel;
  reg write;
  reg [2:0] reg_addr;
  reg [7:0] wdata;
  wire [7:0] rdata;
  wire tx;

  uart #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .sel(sel), .write(write), .reg_addr(reg_addr), .wdata(wdata), .rdata(rdata),
    .tx(tx)
  );

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  // ---- serial receiver model: start bit, 8 data bits lsb first, stop bit
  reg [7:0] rx_bytes [0:15];
  integer rx_count;
  integer rx_bad_frames;
  integer b;
  initial begin
    rx_count = 0;
    rx_bad_frames = 0;
    forever begin
      @(negedge tx); // start bit
      repeat (CLKS_PER_BIT + CLKS_PER_BIT / 2) @(posedge clk); // middle of data bit 0
      for (b = 0; b < 8; b = b + 1) begin
        rx_bytes[rx_count][b] = tx;
        repeat (CLKS_PER_BIT) @(posedge clk);
      end
      if (tx !== 1'b1) rx_bad_frames = rx_bad_frames + 1; // stop bit
      rx_count = rx_count + 1;
    end
  end

  // ---- register access
  task reg_write(input [2:0] a, input [7:0] d);
    begin
      @(negedge clk);
      sel = 1;
      write = 1;
      reg_addr = a;
      wdata = d;
      @(negedge clk);
      sel = 0;
      write = 0;
    end
  endtask

  task reg_expect(input [2:0] a, input [7:0] exp, input string name);
    begin
      @(negedge clk);
      sel = 1;
      write = 0;
      reg_addr = a;
      #1;
      if (rdata !== exp) begin
        test_failed = 1;
        $display("[%0t] error: %s (reg %0d) expected 0x%02x, got 0x%02x", $time, name, a, exp, rdata);
      end
      sel = 0;
    end
  endtask

  task wait_idle;
    begin
      repeat (12 * CLKS_PER_BIT) @(posedge clk);
    end
  endtask

  task expect_tx_idle(input string name);
    begin
      if (tx !== 1'b1) begin
        test_failed = 1;
        $display("[%0t] error: %s tx should idle high", $time, name);
      end
    end
  endtask

  integer frame_clks;
  initial begin
    $dumpfile("./tests/results/test_uart.vcd");
    $dumpvars(0, test_uart);
    test_failed = 0;
    sel = 0;
    write = 0;
    reg_addr = 0;
    wdata = 0;
    rst_n = 0;
    repeat (2) @(posedge clk);
    #1 rst_n = 1;

    // after reset: line idle high, transmitter empty, no interrupt pending, nothing received
    expect_tx_idle("after reset");
    reg_expect(3'd5, 8'h60, "LSR idle");
    reg_expect(3'd2, 8'h01, "IIR");
    reg_expect(3'd0, 8'h00, "RBR");
    reg_expect(3'd6, 8'h00, "MSR");

    // the plain registers hold what is written
    reg_write(3'd1, 8'h05);
    reg_write(3'd3, 8'h83);
    reg_write(3'd4, 8'h0B);
    reg_write(3'd7, 8'hA5);
    reg_expect(3'd1, 8'h05, "IER");
    reg_expect(3'd3, 8'h83, "LCR");
    reg_expect(3'd4, 8'h0B, "MCR");
    reg_expect(3'd7, 8'hA5, "SCR");
    // writing the read only registers changes nothing
    reg_write(3'd5, 8'hFF);
    reg_write(3'd2, 8'hFF);
    reg_expect(3'd5, 8'h60, "LSR after write");
    reg_expect(3'd2, 8'h01, "IIR after write");
    if (rx_count != 0) begin
      test_failed = 1;
      $display("[%0t] error: register writes must not transmit", $time);
    end

    // a deselected write does nothing
    @(negedge clk);
    sel = 0;
    write = 1;
    reg_addr = 3'd0;
    wdata = 8'h11;
    repeat (3) @(negedge clk);
    write = 0;
    if (rx_count != 0 || tx !== 1'b1) begin
      test_failed = 1;
      $display("[%0t] error: deselected write transmitted", $time);
    end

    // send one byte: busy right away, frame takes 10 bit times, then idle again
    reg_write(3'd0, 8'h55);
    reg_expect(3'd5, 8'h00, "LSR busy");
    frame_clks = 0;
    while (dut.busy) begin
      @(posedge clk);
      #1;
      frame_clks = frame_clks + 1;
    end
    // busy is set by the write edge and cleared by the last edge of the frame: the loop saw all
    // but the first of those edges (the reg_expect cycle covered it)
    if (frame_clks + 1 !== 10 * CLKS_PER_BIT) begin
      test_failed = 1;
      $display("[%0t] error: frame took %0d clocks, expected %0d", $time, frame_clks + 1, 10 * CLKS_PER_BIT);
    end
    wait_idle();
    reg_expect(3'd5, 8'h60, "LSR idle again");
    expect_tx_idle("after a frame");
    if (rx_count != 1 || rx_bytes[0] !== 8'h55) begin
      test_failed = 1;
      $display("[%0t] error: expected one byte 0x55, got %0d bytes, first 0x%02x", $time, rx_count, rx_bytes[0]);
    end

    // a write while busy is dropped
    reg_write(3'd0, 8'h41); // 'A'
    reg_write(3'd0, 8'h42); // 'B' arrives while 'A' is going out
    wait_idle();
    if (rx_count != 2 || rx_bytes[1] !== 8'h41) begin
      test_failed = 1;
      $display("[%0t] error: byte written while busy must be dropped, got %0d bytes, second 0x%02x", $time, rx_count, rx_bytes[1]);
    end

    // back to back, polling THRE like a driver does
    reg_write(3'd0, 8'h68); // 'h'
    while (rdata[5] !== 1'b1 || sel !== 1'b1) begin
      @(negedge clk);
      sel = 1;
      write = 0;
      reg_addr = 3'd5;
      #1;
    end
    sel = 0;
    reg_write(3'd0, 8'h69); // 'i'
    wait_idle();
    if (rx_count != 4 || rx_bytes[2] !== 8'h68 || rx_bytes[3] !== 8'h69) begin
      test_failed = 1;
      $display("[%0t] error: expected 'h','i', got %0d bytes 0x%02x 0x%02x", $time, rx_count, rx_bytes[2], rx_bytes[3]);
    end

    // all bit patterns frame correctly, including all zeros and all ones
    reg_write(3'd0, 8'h00);
    wait_idle();
    reg_write(3'd0, 8'hFF);
    wait_idle();
    if (rx_count != 6 || rx_bytes[4] !== 8'h00 || rx_bytes[5] !== 8'hFF) begin
      test_failed = 1;
      $display("[%0t] error: 0x00/0xFF frames, got %0d bytes 0x%02x 0x%02x", $time, rx_count, rx_bytes[4], rx_bytes[5]);
    end
    if (rx_bad_frames != 0) begin
      test_failed = 1;
      $display("[%0t] error: %0d frames without a stop bit", $time, rx_bad_frames);
    end

    finish;
  end

endmodule
