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
  reg rx;
  wire tx;
  wire irq;

  uart #(
    .CLKS_PER_BIT(CLKS_PER_BIT)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .sel(sel), .write(write), .reg_addr(reg_addr), .wdata(wdata), .rdata(rdata),
    .rx(rx), .tx(tx), .irq(irq)
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
  integer fi;
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

  // a real read: sel is held across a clock edge so the side effects of RBR, LSR and IIR happen
  task reg_read_expect(input [2:0] a, input [7:0] exp, input string name);
    begin
      @(negedge clk);
      sel = 1;
      write = 0;
      reg_addr = a;
      #1;
      if (rdata !== exp) begin
        test_failed = 1;
        $display("[%0t] error: %s (read of reg %0d) expected 0x%02x, got 0x%02x", $time, name, a, exp, rdata);
      end
      @(negedge clk);
      sel = 0;
    end
  endtask

  task expect_irq(input exp, input string name);
    begin
      #1;
      if (irq !== exp) begin
        test_failed = 1;
        $display("[%0t] error: %s expected irq=%0d, got %0d", $time, name, exp, irq);
      end
    end
  endtask

  // one frame on rx: start bit, 8 data bits lsb first, stop bit (stop = 0 is a framing error)
  integer rb;
  task rx_send(input [7:0] data, input stop);
    begin
      rx = 0;
      repeat (CLKS_PER_BIT) @(negedge clk);
      for (rb = 0; rb < 8; rb = rb + 1) begin
        rx = data[rb];
        repeat (CLKS_PER_BIT) @(negedge clk);
      end
      rx = stop;
      repeat (CLKS_PER_BIT) @(negedge clk);
      rx = 1;
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
  integer sent_before;
  initial begin
    $dumpfile("./tests/results/test_uart.vcd");
    $dumpvars(0, test_uart);
    test_failed = 0;
    sel = 0;
    write = 0;
    reg_addr = 0;
    wdata = 0;
    rx = 1;
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
    reg_write(3'd3, 8'h1B);
    reg_write(3'd4, 8'h0B);
    reg_write(3'd7, 8'hA5);
    reg_expect(3'd1, 8'h05, "IER");
    reg_expect(3'd3, 8'h1B, "LCR");
    reg_expect(3'd4, 8'h0B, "MCR");
    reg_expect(3'd7, 8'hA5, "SCR");
    // writing the read only registers changes nothing
    reg_write(3'd5, 8'hFF);
    reg_write(3'd2, 8'hFE);
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


    // ================= receiver =================
    reg_write(3'd1, 8'h00);
    reg_write(3'd3, 8'h03);
    reg_expect(3'd5, 8'h60, "LSR before receiving");

    // a byte arrives: DR, then RBR returns it and clears DR
    rx_send(8'h5A, 1'b1);
    repeat (4) @(negedge clk);
    reg_expect(3'd5, 8'h61, "LSR DR");
    reg_read_expect(3'd0, 8'h5A, "RBR");
    reg_expect(3'd5, 8'h60, "LSR after reading RBR");

    // all bit patterns
    rx_send(8'h00, 1'b1);
    repeat (4) @(negedge clk);
    reg_read_expect(3'd0, 8'h00, "RBR 0x00");
    rx_send(8'hFF, 1'b1);
    repeat (4) @(negedge clk);
    reg_read_expect(3'd0, 8'hFF, "RBR 0xFF");
    rx_send(8'hA5, 1'b1);
    repeat (4) @(negedge clk);
    reg_read_expect(3'd0, 8'hA5, "RBR 0xA5");

    // received data interrupt, enabled by IER bit 0, cleared by reading RBR
    reg_write(3'd1, 8'h01);
    expect_irq(0, "no data, no interrupt");
    rx_send(8'h41, 1'b1);
    repeat (2) @(negedge clk);
    expect_irq(1, "received data interrupt");
    reg_expect(3'd2, 8'h04, "IIR received data");
    reg_read_expect(3'd0, 8'h41, "RBR 0x41");
    expect_irq(0, "RBR read clears the interrupt");
    reg_expect(3'd2, 8'h01, "IIR idle");
    reg_write(3'd1, 8'h00);
    rx_send(8'h42, 1'b1);
    repeat (2) @(negedge clk);
    expect_irq(0, "data received with the interrupt disabled");
    reg_write(3'd1, 8'h01);
    expect_irq(1, "enabling the interrupt raises it for waiting data");
    reg_read_expect(3'd0, 8'h42, "RBR 0x42");

    // a byte that is read while the next one is still coming does not overrun
    rx_send(8'h31, 1'b1);
    fork
      rx_send(8'h32, 1'b1);
      begin
        repeat (3 * CLKS_PER_BIT) @(negedge clk);
        reg_read_expect(3'd0, 8'h31, "RBR first of two back to back");
      end
    join
    repeat (4) @(negedge clk);
    reg_read_expect(3'd0, 8'h32, "RBR second of two back to back");
    reg_expect(3'd5, 8'h60, "no overrun when the reader keeps up");

    // overrun: the unread byte stays, the new one is lost, OE is set until LSR is read
    reg_write(3'd1, 8'h05);
    rx_send(8'h11, 1'b1);
    rx_send(8'h22, 1'b1);
    repeat (4) @(negedge clk);
    reg_expect(3'd5, 8'h63, "LSR DR and OE");
    expect_irq(1, "line status interrupt");
    reg_expect(3'd2, 8'h06, "IIR line status wins over received data");
    reg_read_expect(3'd5, 8'h63, "LSR read");
    reg_expect(3'd5, 8'h61, "OE cleared by the LSR read, DR stays");
    reg_expect(3'd2, 8'h04, "IIR received data");
    reg_read_expect(3'd0, 8'h11, "the first byte was kept");
    reg_expect(3'd5, 8'h60, "nothing left");
    expect_irq(0, "all clear");

    // framing error (stop bit low): the byte is delivered, FE is set, and a break doesn't make more bytes
    rx = 0;
    repeat (40 * CLKS_PER_BIT) @(negedge clk); // a break: low for 40 bit times
    rx = 1;
    repeat (2 * CLKS_PER_BIT) @(negedge clk);
    reg_expect(3'd5, 8'h69, "LSR DR and FE");
    reg_read_expect(3'd0, 8'h00, "RBR after the break");
    reg_read_expect(3'd5, 8'h68, "LSR read returns FE");
    reg_expect(3'd5, 8'h60, "FE cleared, no further bytes from the break");
    rx_send(8'h77, 1'b1);
    repeat (2) @(negedge clk);
    reg_read_expect(3'd0, 8'h77, "a normal byte after the break");
    rx_send(8'h99, 1'b0);
    repeat (2) @(negedge clk);
    reg_read_expect(3'd5, 8'h69, "a frame with a low stop bit sets FE and delivers the byte");
    reg_read_expect(3'd0, 8'h99, "RBR of the framing error byte");
    reg_read_expect(3'd5, 8'h60, "clear");

    // a glitch shorter than half a bit is not a start bit
    rx = 0;
    repeat (1) @(negedge clk);
    rx = 1;
    repeat (12 * CLKS_PER_BIT) @(negedge clk);
    reg_expect(3'd5, 8'h60, "glitch ignored");

    // ================= transmit empty interrupt =================
    reg_write(3'd1, 8'h00);
    wait_idle();
    reg_write(3'd1, 8'h02);
    expect_irq(1, "THRE interrupt raised by enabling it while empty");
    reg_expect(3'd2, 8'h02, "IIR THR empty");
    reg_read_expect(3'd2, 8'h02, "IIR read");
    expect_irq(0, "IIR read clears THRE");
    reg_expect(3'd2, 8'h01, "IIR idle after clearing");
    reg_write(3'd0, 8'h4F);
    expect_irq(0, "no interrupt while sending");
    wait_idle();
    expect_irq(1, "THRE interrupt when the byte is gone");
    reg_write(3'd0, 8'h4B);
    expect_irq(0, "writing THR clears it");
    wait_idle();
    expect_irq(1, "and it comes back");
    // received data has priority over THR empty
    reg_write(3'd1, 8'h03);
    rx_send(8'h12, 1'b1);
    repeat (2) @(negedge clk);
    reg_expect(3'd2, 8'h04, "IIR data before THR empty");
    reg_read_expect(3'd0, 8'h12, "RBR");
    reg_expect(3'd2, 8'h02, "IIR THR empty");
    reg_write(3'd1, 8'h00);
    expect_irq(0, "interrupts disabled");
    reg_read_expect(3'd2, 8'h01, "IIR with nothing enabled");

    // ================= divisor latches =================
    reg_write(3'd1, 8'h01);
    rx_send(8'h3C, 1'b1);
    repeat (2) @(negedge clk);
    sent_before = rx_count;
    reg_write(3'd3, 8'h83); // DLAB
    reg_write(3'd0, 8'h0D); // DLL: must not transmit
    reg_write(3'd1, 8'h07); // DLM: must not change IER
    reg_read_expect(3'd0, 8'h0D, "DLL");
    reg_read_expect(3'd1, 8'h07, "DLM");
    wait_idle();
    if (rx_count != sent_before) begin
      test_failed = 1;
      $display("[%0t] error: a DLL write transmitted (%0d bytes seen, %0d before)", $time, rx_count, sent_before);
    end
    reg_expect(3'd5, 8'h61, "reading DLL did not consume the received byte");
    reg_write(3'd3, 8'h03);
    reg_expect(3'd1, 8'h01, "IER untouched by the DLM write");
    reg_read_expect(3'd0, 8'h3C, "RBR is back with DLAB clear");

    // ================= 16550A fifos =================
    reg_write(3'd1, 8'h00);
    reg_read_expect(3'd2, 8'h01, "IIR before fifos are enabled has no fifo bits");
    reg_write(3'd2, 8'hC1); // enable, trigger level 14
    reg_expect(3'd2, 8'hC1, "IIR fifo bits");

    // transmit: 5 bytes written back to back are all sent, in order
    sent_before = rx_count;
    reg_write(3'd0, 8'h41);
    reg_write(3'd0, 8'h42);
    reg_write(3'd0, 8'h43);
    reg_write(3'd0, 8'h44);
    reg_write(3'd0, 8'h45);
    reg_expect(3'd5, 8'h00, "LSR THRE and TEMT clear while the fifo holds bytes");
    repeat (60 * CLKS_PER_BIT) @(posedge clk);
    if (rx_count != sent_before + 5 || rx_bytes[sent_before] !== 8'h41 || rx_bytes[sent_before+4] !== 8'h45) begin
      test_failed = 1;
      $display("[%0t] error: fifo transmit sent %0d bytes, first 0x%02x last 0x%02x", $time,
               rx_count - sent_before, rx_bytes[sent_before], rx_bytes[sent_before+4]);
    end
    reg_expect(3'd5, 8'h60, "LSR THRE and TEMT after the fifo drained");

    // receive: 5 bytes queue up, trigger level 14 means no data interrupt yet, only the timeout
    reg_write(3'd1, 8'h01);
    rx_send(8'h51, 1'b1);
    rx_send(8'h52, 1'b1);
    rx_send(8'h53, 1'b1);
    rx_send(8'h54, 1'b1);
    rx_send(8'h55, 1'b1);
    repeat (2) @(negedge clk);
    expect_irq(0, "below the trigger level, before the timeout");
    reg_expect(3'd5, 8'h61, "LSR DR with 5 bytes");
    repeat (45 * CLKS_PER_BIT) @(posedge clk);
    expect_irq(1, "character timeout");
    reg_expect(3'd2, 8'hCC, "IIR character timeout");
    reg_read_expect(3'd0, 8'h51, "fifo byte 1");
    reg_read_expect(3'd0, 8'h52, "fifo byte 2");
    reg_read_expect(3'd0, 8'h53, "fifo byte 3");
    expect_irq(0, "timeout restarts after a read");
    reg_read_expect(3'd0, 8'h54, "fifo byte 4");
    reg_read_expect(3'd0, 8'h55, "fifo byte 5");
    reg_expect(3'd5, 8'h60, "LSR empty after the reads");
    expect_irq(0, "empty fifo, no interrupt");

    // trigger level 4
    reg_write(3'd2, 8'h41);
    rx_send(8'h61, 1'b1);
    rx_send(8'h62, 1'b1);
    rx_send(8'h63, 1'b1);
    repeat (2) @(negedge clk);
    expect_irq(0, "3 bytes, level 4");
    rx_send(8'h64, 1'b1);
    repeat (2) @(negedge clk);
    expect_irq(1, "4 bytes, level 4");
    reg_expect(3'd2, 8'hC4, "IIR received data");

    // 16 bytes fit, the 17th overruns and the first 16 stay
    reg_write(3'd2, 8'hC3); // bit 1: clear the receive fifo
    reg_expect(3'd5, 8'h60, "receive fifo cleared by FCR bit 1");
    for (fi = 0; fi < 17; fi = fi + 1) rx_send(8'hA0 + fi[7:0], 1'b1);
    repeat (2) @(negedge clk);
    reg_expect(3'd5, 8'h63, "LSR DR and OE with 17 bytes sent");
    for (fi = 0; fi < 16; fi = fi + 1) reg_read_expect(3'd0, 8'hA0 + fi[7:0], "fifo byte");
    reg_read_expect(3'd5, 8'h62, "fifo empty after 16 reads, OE still set until LSR is read");
    reg_expect(3'd5, 8'h60, "OE cleared by the LSR read");

    // switching the fifos off goes back to 16450 behaviour
    reg_write(3'd2, 8'h00);
    reg_expect(3'd2, 8'h01, "IIR fifo bits clear");
    reg_write(3'd1, 8'h00);

    finish;
  end

endmodule
