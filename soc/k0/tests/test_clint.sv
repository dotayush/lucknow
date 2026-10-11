`timescale 1ns/1ps

module test_clint;

  localparam real CLK_PERIOD = 10.0;
  localparam real CLK_HALF_PERIOD = CLK_PERIOD / 2.0;
  localparam [15:2] MSIP = 14'h0000 >> 2;
  localparam [15:2] MTIMECMP_LO = 16'h4000 >> 2;
  localparam [15:2] MTIMECMP_HI = 16'h4004 >> 2;
  localparam [15:2] MTIME_LO = 16'hBFF8 >> 2;
  localparam [15:2] MTIME_HI = 16'hBFFC >> 2;

  reg test_failed;
  task finish;
    begin
      if (test_failed) $display("Test failed!");
      else $display("Test passed!");
      $finish;
    end
  endtask

  reg clk;
  reg rst_n;
  reg sel;
  reg write;
  reg [15:2] reg_addr;
  reg [31:0] wdata;
  wire [31:0] rdata;
  wire [63:0] mtime;
  wire msip;
  wire mtip;

  clint dut (
    .clk(clk), .rst_n(rst_n), .sel(sel), .write(write), .reg_addr(reg_addr),
    .wdata(wdata), .rdata(rdata), .mtime(mtime), .msip(msip), .mtip(mtip)
  );

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  task store(input [15:2] addr, input [31:0] data);
    begin
      @(negedge clk);
      sel = 1;
      write = 1;
      reg_addr = addr;
      wdata = data;
      @(negedge clk);
      sel = 0;
      write = 0;
    end
  endtask

  task expect32(input string what, input [15:2] addr, input [31:0] expected);
    begin
      reg_addr = addr;
      #1;
      if (rdata !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected=0x%08x, got=0x%08x", $time, what, expected, rdata);
      end else begin
        $display("[%0t] OK: %s = 0x%08x", $time, what, rdata);
      end
    end
  endtask

  task expect_bit(input string what, input actual, input expected);
    begin
      if (actual !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected=%0d, got=%0d", $time, what, expected, actual);
      end else begin
        $display("[%0t] OK: %s = %0d", $time, what, actual);
      end
    end
  endtask

  reg [63:0] t0;

  initial begin
    $dumpfile("./tests/results/test_clint.vcd");
    $dumpvars(0, dut);
    test_failed = 0;
    sel = 0;
    write = 0;
    reg_addr = 0;
    wdata = 0;
    rst_n = 0;
    #(2 * CLK_PERIOD);
    rst_n = 1;

    // reset state: no interrupt, mtimecmp is all ones
    expect_bit("msip at reset", msip, 0);
    expect_bit("mtip at reset", mtip, 0);
    expect32("mtimecmp low at reset", MTIMECMP_LO, 32'hFFFF_FFFF);
    expect32("mtimecmp high at reset", MTIMECMP_HI, 32'hFFFF_FFFF);

    // mtime counts every clock and is readable by halves
    @(negedge clk);
    t0 = mtime;
    repeat (5) @(negedge clk);
    if (mtime !== t0 + 5) begin
      test_failed = 1;
      $display("error: mtime did not count 5 clocks: %0d -> %0d", t0, mtime);
    end
    expect32("mtime low", MTIME_LO, mtime[31:0]);
    expect32("mtime high", MTIME_HI, 32'h0);

    // software interrupt: only bit 0 is stored
    store(MSIP, 32'hFFFF_FFFF);
    expect_bit("msip set", msip, 1);
    expect32("msip reads back bit 0 only", MSIP, 32'h1);
    store(MSIP, 32'hFFFF_FFFE);
    expect_bit("msip cleared", msip, 0);

    // timer interrupt: level, while mtime >= mtimecmp
    store(MTIMECMP_HI, 32'h0);
    store(MTIMECMP_LO, mtime[31:0] + 6);
    expect_bit("mtip before the deadline", mtip, 0);
    repeat (8) @(negedge clk);
    expect_bit("mtip after the deadline", mtip, 1);
    store(MTIMECMP_LO, 32'hFFFF_FFFF); // moving the deadline away clears it
    expect_bit("mtip cleared by a later mtimecmp", mtip, 0);

    // the high word counts: mtimecmp needs both halves
    store(MTIMECMP_HI, 32'h0000_0002);
    store(MTIMECMP_LO, 32'h0);
    store(MTIME_HI, 32'h0000_0001);
    store(MTIME_LO, 32'hFFFF_FFFC); // last write: the count carries into the high word 4 clocks later
    expect_bit("high half decides", mtip, 0);
    repeat (8) @(negedge clk);
    expect_bit("mtip after the carry", mtip, 1);
    expect32("mtime high carried", MTIME_HI, 32'h0000_0002);

    // unused offsets in the window read 0 and ignore writes; a read does not write
    store(14'h0010 >> 2, 32'hDEAD_BEEF);
    expect32("unused offset", 14'h0010 >> 2, 32'h0);
    expect32("msip untouched by the unused write", MSIP, 32'h0);

    // sel low: a write on the bus does nothing
    @(negedge clk);
    write = 1;
    reg_addr = MSIP;
    wdata = 1;
    @(negedge clk);
    write = 0;
    expect_bit("write without sel", msip, 0);

    finish;
  end
endmodule
