`timescale 1ns/1ps

module test_plic;

  localparam real CLK_HALF_PERIOD = 5.0;
  localparam [25:2] PRIORITY_BASE = 24'h0;
  localparam [25:2] PENDING = 26'h1000 >> 2;
  localparam [25:2] ENABLE = 26'h2000 >> 2;
  localparam [25:2] THRESHOLD = 26'h20_0000 >> 2;
  localparam [25:2] CLAIM = 26'h20_0004 >> 2;

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
  reg [31:1] src;
  reg sel;
  reg write;
  reg [25:2] reg_addr;
  reg [31:0] wdata;
  wire [31:0] rdata;
  wire meip;

  plic #(.NUM_SOURCES(31)) dut (
    .clk(clk), .rst_n(rst_n), .src(src),
    .sel(sel), .write(write), .reg_addr(reg_addr), .wdata(wdata), .rdata(rdata),
    .meip(meip)
  );

  initial begin
    clk = 0;
    forever #(CLK_HALF_PERIOD) clk = !clk;
  end

  task store(input [25:2] addr, input [31:0] data);
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

  // a read with its side effects: sel is held across one clock edge
  task load(input [25:2] addr, input [31:0] expected, input string what);
    begin
      @(negedge clk);
      sel = 1;
      write = 0;
      reg_addr = addr;
      #1;
      if (rdata !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected 0x%08x, got 0x%08x", $time, what, expected, rdata);
      end
      @(negedge clk);
      sel = 0;
    end
  endtask

  // look without touching: sel low, the register value is still there
  task peek(input [25:2] addr, input [31:0] expected, input string what);
    begin
      reg_addr = addr;
      #1;
      if (rdata !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected 0x%08x, got 0x%08x", $time, what, expected, rdata);
      end
    end
  endtask

  task expect_meip(input expected, input string what);
    begin
      repeat (2) @(negedge clk);
      if (meip !== expected) begin
        test_failed = 1;
        $display("[%0t] error: %s expected meip=%0d, got %0d", $time, what, expected, meip);
      end
    end
  endtask

  initial begin
    $dumpfile("./tests/results/test_plic.vcd");
    $dumpvars(0, dut);
    test_failed = 0;
    sel = 0;
    write = 0;
    reg_addr = 0;
    wdata = 0;
    src = 0;
    rst_n = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;

    // reset: everything zero, nothing to claim
    expect_meip(0, "meip at reset");
    peek(PENDING, 0, "pending at reset");
    peek(ENABLE, 0, "enable at reset");
    peek(THRESHOLD, 0, "threshold at reset");
    peek(CLAIM, 0, "claim at reset");
    peek(PRIORITY_BASE + 1, 0, "priority 1 at reset");

    // priorities keep PRIORITY_BITS (3), source 0 and the registers past the last source don't exist
    store(PRIORITY_BASE + 5, 32'hFFFF_FFFF);
    peek(PRIORITY_BASE + 5, 7, "priority of source 5");
    store(PRIORITY_BASE + 0, 32'h5);
    peek(PRIORITY_BASE + 0, 0, "priority of source 0");
    store(PRIORITY_BASE + 32, 32'h5);
    peek(PRIORITY_BASE + 32, 0, "after the last source");
    peek(PRIORITY_BASE + 5, 7, "source 5 untouched by neighbours");
    // pending is read only, enable has no bit 0
    store(PENDING, 32'hFFFF_FFFF);
    peek(PENDING, 0, "pending ignores writes");
    store(ENABLE, 32'hFFFF_FFFF);
    peek(ENABLE, 32'hFFFF_FFFE, "enable bits 31..1");
    store(ENABLE, 0);
    store(THRESHOLD, 32'hFFFF_FFFF);
    peek(THRESHOLD, 7, "threshold keeps 3 bits");
    store(THRESHOLD, 0);
    // other offsets read 0 and ignore writes
    store(26'h3000 >> 2, 32'hDEAD_BEEF);
    peek(26'h3000 >> 2, 0, "unused offset");
    store(26'h20_0008 >> 2, 32'hDEAD_BEEF);
    peek(26'h20_0008 >> 2, 0, "unused offset after claim");
    peek(PENDING + 1, 0, "pending word 1 does not exist");

    // basic flow of one source: raise, interrupt, claim, complete
    store(PRIORITY_BASE + 3, 1);
    store(ENABLE, 32'h0000_0008);
    src[3] = 1;
    expect_meip(1, "source 3 interrupts");
    peek(PENDING, 32'h0000_0008, "pending shows source 3");
    peek(CLAIM, 3, "claim register shows the id without taking it");
    expect_meip(1, "peeking did not claim");
    load(CLAIM, 3, "claim");
    expect_meip(0, "claimed source is held");
    peek(PENDING, 0, "pending cleared by the claim");
    load(CLAIM, 0, "nothing more to claim while source 3 is in flight");
    store(CLAIM, 3); // complete, the line is still high
    expect_meip(1, "still asserted: pending again after completion");
    load(CLAIM, 3, "claim again");
    src[3] = 0; // handled, line dropped before the completion
    store(CLAIM, 3);
    expect_meip(0, "line low at completion: nothing pending");
    load(CLAIM, 0, "claim finds nothing");

    // priority arbitration and ties: highest priority first, lowest id among equals
    store(ENABLE, 32'h0000_00FC); // sources 2..7
    store(PRIORITY_BASE + 2, 1);
    store(PRIORITY_BASE + 5, 4);
    store(PRIORITY_BASE + 7, 4);
    src[2] = 1;
    src[7] = 1;
    src[5] = 1;
    expect_meip(1, "three pending");
    load(CLAIM, 5, "highest priority, lowest id");
    expect_meip(1, "more to come");
    load(CLAIM, 7, "the other of equal priority");
    load(CLAIM, 2, "the low priority one last");
    expect_meip(0, "all in flight");
    src = 0;
    store(CLAIM, 5);
    store(CLAIM, 7);
    store(CLAIM, 2);
    expect_meip(0, "all completed");

    // threshold: only priorities above it count; priority 0 never interrupts
    store(PRIORITY_BASE + 5, 4);
    store(THRESHOLD, 4);
    src[5] = 1;
    expect_meip(0, "priority equal to the threshold does not interrupt");
    peek(PENDING, 32'h0000_0020, "but it is pending");
    store(THRESHOLD, 3);
    expect_meip(1, "threshold below the priority");
    store(THRESHOLD, 0);
    store(PRIORITY_BASE + 5, 0);
    expect_meip(0, "priority 0 never interrupts, even with threshold 0");
    store(PRIORITY_BASE + 5, 4);
    load(CLAIM, 5, "claim");
    src[5] = 0;
    store(CLAIM, 5);

    // a source that is not enabled is pending but silent; enabling it interrupts
    store(ENABLE, 0);
    src[6] = 1;
    store(PRIORITY_BASE + 6, 2);
    expect_meip(0, "disabled source");
    peek(PENDING, 32'h0000_0040, "pending regardless of enable");
    store(ENABLE, 32'h0000_0040);
    expect_meip(1, "enabled now");
    load(CLAIM, 6, "claim");

    // a completion of a source that isn't enabled is ignored: the source stays held
    store(ENABLE, 0);
    store(CLAIM, 6);
    store(ENABLE, 32'h0000_0040);
    expect_meip(0, "completion while disabled was ignored");
    store(CLAIM, 6);
    expect_meip(1, "completed properly, still asserted");
    load(CLAIM, 6, "claim");
    src[6] = 0;
    store(CLAIM, 6);

    // completions that mean nothing: an id that wasn't claimed, id 0, ids past the last source, junk in the upper bits
    src[4] = 1;
    store(PRIORITY_BASE + 4, 1);
    store(ENABLE, 32'h0000_0010);
    load(CLAIM, 4, "claim 4");
    store(CLAIM, 32'h0000_0100 | 4); // not an id: ignored
    expect_meip(0, "junk in the upper bits is no completion");
    store(CLAIM, 0);
    store(CLAIM, 32);
    store(CLAIM, 3); // a different source
    expect_meip(0, "source 4 still held");
    store(CLAIM, 4);
    expect_meip(1, "a real completion");
    load(CLAIM, 4, "claim 4 again");
    src = 0;
    store(CLAIM, 4);
    expect_meip(0, "done");

    // a read that isn't selected has no side effect, a write to the claim register does not claim
    src[4] = 1;
    expect_meip(1, "4 pending");
    @(negedge clk);
    write = 0;
    reg_addr = CLAIM;
    repeat (3) @(negedge clk);
    expect_meip(1, "reading without sel leaves it pending");
    load(CLAIM, 4, "claim 4");
    src = 0;
    store(CLAIM, 4);

    finish;
  end

endmodule
